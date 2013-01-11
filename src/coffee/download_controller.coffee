# Manages the process of downloading files from their origin site.
class DownloadController
  constructor: ->
    @fileCount = 0
    @files = {}
    @xhrs = {}
    @onPermissionDenied = new Dropbox.EventSource
    @onStateChange = new Dropbox.EventSource

  # @property {Dropbox.EventSource<null>} non-cancelable event fired when the
  #   user denies the temporary permissions needed to download a file;
  #   listeners should inform the user that their download was canceled
  onPermissionDenied: null

  # @property {Dropbox.EventSource<DownloadFile>} non-cancelable event fired
  #   when a file download completes or stops due to an error; this event does
  #   not fire when a download is canceled
  onStateChange: null

  # Adds a file to the list of files to be downloaded.
  #
  # @param {DropshipFile} file descriptor for the file to be downloaded
  # @param {function()} callback called when the file is successfully added for
  #   download; not called if the download is aborted due to permission issues
  # @return {DownloadController} this
  addFile: (file, callback) ->
    if @files[file.uid]
      callback()
      return @

    @getPermissions true, =>
      @fileCount += 1
      @files[file.uid] = file

      # NOTE: using Dropbox.Xhr for brevity; for robustness, XMLHttpRequest
      #       should be used directly
      dbXhr = new Dropbox.Xhr 'GET', file.url
      dbXhr.setResponseType 'blob'
      if file.referrer
        dbXhr.setHeader 'Referer', file.referrer
      dbXhr.prepare()
      @xhrs[file.uid] = dbXhr.xhr
      dbXhr.xhr.addEventListener 'progress', (event) =>
        @onXhrProgress file, event
      dbXhr.send (error, blob) => @onXhrResponse file, error, blob
      callback()

  # Cancels the download process for a file.
  #
  # @param {DropshipFile} file descriptor for the file whose download will be
  #   canceled
  # @param {function()} callback called when the file download is canceled
  # @return {DownloadController} this
  cancelFile: (file, callback) ->
    # Ignore already canceled / completed downloads.
    unless @xhrs[file.uid]
      callback()
      return @

    try
      @xhrs[file.uid].abort()
    catch error
      # Ignore the XHR object complaining.

    @removeFile file, callback

  # Called when an XHR downloading a file completes.
  #
  # @param {DropshipFile} file the file being download
  # @param {?Dropbox.ApiError} error set if the XHR went wrong
  # @param {?Blob} blob the downloaded file
  onXhrResponse: (file, error, blob) ->
    # Ignore canceled downloads.
    return unless @xhrs[file.uid]

    if error
      file.setDownloadError error
    else if blob
      file.setContents blob

    @removeFile file, =>
      @onStateChange.dispatch file

  # Called when an XHR downloading a file makes progress.
  onXhrProgress: (file, event) ->
    # Ignore canceled downloads.
    unless @xhrs[file.uid]
      event.target.abort()
      return

    downloadedBytes = event.loaded
    totalBytes = if event.lengthComputable then event.total else null
    file.setDownloadProgress downloadedBytes, totalBytes
    @onStateChange.dispatch file

  # Removes one of the files tracked for download.
  #
  # @private Called by cancelFile and onXhrResponse.
  # @return {UploadController} this
  removeFile: (file, callback) ->
    if @files[file.uid]
      delete @xhrs[file.uid]
      delete @files[file.uid]
      @fileCount -= 1

    @getPermissions false, callback

  # Manages temporary Chrome permissions.
  #
  # When the first file is queued for download, we temporarily request the
  # permission to access all the user's files (scary). When we have nothing
  # left to download, we drop the permission.
  #
  # @param {Boolean} addFile true if a download will be started, false if a
  #   download just ended
  # @param {function()} callback called when the permissions are set correctly;
  #   if the user denies some permissions, the callback is not called at all;
  #   instead,
  #
  # @return {DownloadController} this
  getPermissions: (newDownload, callback) ->
    if newDownload
      chrome.permissions.contains origins: ['<all_urls>'], (allowed) =>
        if allowed
          return callback()
        chrome.permissions.request origins: ['<all_urls>'], (granted) =>
          if granted
            return callback()
          @onPermissionDenied.dispatch null
    else
      unless @fileCount is 0
        return callback()
      chrome.permissions.contains origins: ['<all_urls>'], (allowed) ->
        unless allowed
          return callback()
        chrome.permissions.remove origins: ['<all_urls>'], -> callback()
    @

window.DownloadController = DownloadController
