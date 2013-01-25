# Manages the process of uploading files to Dropbox.
class UploadController
  # @param {Dropbox.Chrome} dropboxChrome Chrome extension-friendly wraper for
  #   the Dropbox client to be used for uploading
  # @param {Options}
  constructor: (@dropboxChrome, @options) ->
    @files = {}
    @xhrs = {}
    @onStateChange = new Dropbox.EventSource

  # @property {Dropbox.EventSource<DropshipFile>} non-cancelable event fired
  #   when a file upload makes progress, completes, or stops due to an error;
  #   this event does not fire when an upload is canceled
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

    if file.size < @atomicUploadCutoff
      @atomicUpload file, callback
    else
      @resumableUploadStep file, callback

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

  # One-step upload method that either works or fails.
  #
  # This is suitable for smaller files. It does not work at all for very large
  # (> 150MB) files, and has unreliable progress metering for medium (> 10MB)
  # files.
  #
  # @param {DropshipFile} file descriptor for the file to be uploaded
  # @param {function()} callback called when the file is successfully added for
  #   upload
  # @return {UploadController} this
  atomicUpload: (file, callback) ->
    @dropboxChrome.client (client) =>
      @options.items (items) =>
        xhrListener = (dbXhr) =>
          xhr = dbXhr.xhr
          xhr.upload.addEventListener 'progress', (event) =>
            @onXhrUploadProgress file, xhr, event
        filePath = @options.downloadPath file, items
        client.onXhr.addListener xhrListener
        @xhrs[file.uid] = client.writeFile filePath, file.blob,
            noOverwrite: true, (error, stat) => @onDropboxWrite file, error, stat
        client.onXhr.removeListener xhrListener
        callback()
    @

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

  # Multi-step upload method that can be resumed if one step fails.
  #
  # Performing one step is much slower than a simple upload for small files, so
  # this method is only suitable for large files, where the time for uploading
  # the data dwarves the step overhead.
  #
  # @param {DropshipFile} file descriptor for the file to be uploaded
  # @param {function()} callback called when the file is successfully added for
  #   upload
  # @return {UploadController} this
  resumableUploadStep: (file, callback) ->
    @dropboxChrome.client (client) =>
      xhrListener = (dbXhr) =>
        xhr = dbXhr.xhr
        xhr.upload.addEventListener 'progress', (event) =>
          @onXhrUploadProgress file, xhr, event
      client.onXhr.addListener xhrListener
      file.uploadCursor or= new Dropbox.UploadCursor
      cursor = file.uploadCursor
      stepBlob = file.blob.slice cursor.offset, cursor.offset + @uploadStepSize
      @xhrs[file.uid] = client.resumableUploadStep stepBlob, cursor,
          (error, cursor) => @onDropboxWriteStep file, error, cursor
      client.onXhr.removeListener xhrListener
      callback()
    @

  # Finishing step in the multi-step upload method.
  #
  # @param {DropshipFile} file descriptor for the file getting uploaded
  # @param {function()} callback called when the file is successfully added for
  #   upload
  # @return {UploadController} this
  resumableUploadFinish: (file, callback) ->
    @dropboxChrome.client (client) =>
      @options.items (items) =>
        filePath = @options.downloadPath file, items
        @xhrs[file.uid] = client.resumableUploadFinish filePath,
            file.uploadCursor, noOverwrite: true,
            (error, stat) => @onDropboxWrite file, error, stat
        callback()
    @

  # Called when a step in a multi-step Dropbox write request completes.
  #
  # @param {DropshipFile} file the file being uploaded
  # @param {?Dropbox.ApiError} error set if the API call went wrong
  # @param {Dropbox.Stat} stat the file's metadata in Dropbox
  onDropboxWriteStep: (file, error, cursor) ->
    # Ignore canceled uploads.
    return unless @xhrs[file.uid]

    if error
      file.setUploadError error
      @removeFile file, =>
        @onStateChange.dispatch file
      return

    file.setUploadCursor cursor
    if cursor.offset is file.size
      @resumableUploadFinish file, =>
        @onStateChange.dispatch file
    else
      @resumableUploadStep file, =>
        @onStateChange.dispatch file

  # Called when an XHR uploading a file makes progress.
  #
  # @param {DropshipFile} file descriptor for the file getting uploaded
  # @param {XMLHttpRequet} xhr the XHR making progress
  # @param
  onXhrUploadProgress: (file, xhr, event) ->
    # Ignore canceled downloads.
    unless @xhrs[file.uid]
      xhr.abort()
      return

    uploadSize = if file.uploadCursor
      @uploadStepSize
    else
      file.size

    uploadedBytes = event.loaded
    totalBytes = if event.lengthComputable then event.total else null
    if totalBytes
      uploadOverhead = totalBytes - uploadSize
      uploadOverhead = 0 if uploadOverhead < 0
      uploadedBytes -= uploadOverhead
      uploadedBytes = 0 if uploadedBytes < 0

    if file.uploadCursor
      uploadedBytes += file.uploadCursor.offset
    file.setUploadProgress uploadedBytes - uploadOverhead
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

  # Files above this size are uploaded using the resumable method.
  atomicUploadCutoff: 4 * 1024 * 1024

  # The size of a step in a multi-step upload.
  uploadStepSize: 4 * 1024 * 1024

window.UploadController = UploadController
