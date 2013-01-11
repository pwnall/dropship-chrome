# Manages the process of uploading files to Dropbox.
class UploadController
  # @param {Dropbox.Chrome} dropboxChrome Chrome extension-friendly wraper for
  #   the Dropbox client to be used for uploading
  constructor: (@dropboxChrome) ->
    @files = {}
    @xhrs = {}
    @onStateChange = new Dropbox.EventSource

  # @property {Dropbox.EventSource<DownloadFile>} non-cancelable event fired
  #   when a file upload completes or stops due to an error; this event does
  #   not fire when an upload is canceled
  onStateChange: null

  # Adds a file to the list of files to be uploaded.
  #
  # @param {DropshipFile} file descriptor for the file to be uploaded
  # @param {function()} callback called when the file is successfully added for
  #   upload
  # @return {UploadController} this
  addFile: (file, callback) ->
    if @files[file.uid]
      callback()
      return @
    @files[file.uid] = file

    @dropboxChrome.client (client) =>
      xhrListener = (dbXhr) =>
        xhr = dbXhr.xhr
        xhr.upload.addEventListener 'progress', (event) =>
          @onXhrUploadProgress file, xhr, event
      client.onXhr.addListener xhrListener
      @xhrs[file.uid] = client.writeFile file.basename(), file.blob,
          noOverwrite: true, (error, stat) => @onDropboxWrite file, error, stat
      client.onXhr.removeListener xhrListener
      callback()
    @

  # Cancels a Dropbox file write.
  #
  # @param {DropshipFile} file descriptor for the file whose upload will be
  #   canceled
  # @param {function()} callback called when the file upload is canceled
  # @return {UploadController} this
  cancelFile: (file, callback) ->
    # Ignore already canceled / completed uploads.
    unless @xhrs[file.uid]
      callback()
      return @

    delete @xhrs[file.uid]  # Avoid getting an error callback.
    try
      @xhrs[file.uid].abort()
    catch error
      # Ignore the XHR object complaining.

    @removeFile file, callback

  # Called when a Dropbox write request completes.
  #
  # @param {DropshipFile} file the file being uploaded
  # @param {?Dropbox.ApiError} error set if the API call went wrong
  # @param {Dropbox.Stat} stat the file's metadata in Dropbox
  onDropboxWrite: (file, error, stat) ->
    # Ignore canceled uploads.
    return unless @xhrs[file.uid]

    if error
      file.setUploadError error
    else
      file.setDropboxStat stat

    @removeFile file, =>
      @onStateChange.dispatch file

  # Called when an XHR uploading a file makes progress.
  onXhrUploadProgress: (file, xhr, event) ->
    # Ignore canceled uploads.
    # Ignore canceled downloads.
    unless @xhrs[file.uid]
      xhr.abort()
      return

    uploadedBytes = event.loaded
    totalBytes = if event.lengthComputable then event.total else null
    file.setUploadProgress uploadedBytes, totalBytes
    @onStateChange.dispatch file

  # Removes one of the files tracked for upload.
  #
  # @private Called by cancelFile and onDropboxWrite.
  # @return {UploadController} this
  removeFile: (file, callback) ->
    if @files[file.uid]
      delete @xhrs[file.uid]
      delete @files[file.uid]
    callback()
    @

window.UploadController = UploadController
