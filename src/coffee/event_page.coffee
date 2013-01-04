# Model class that tracks all the in-progress and completed downloads.
#
# This class is responsible for persisting the files' contents and metadata to
# IndexedDB.
class DropshipList
  constructor: ->
    @files = {}

  # Adds a file to the list of files to be downloaded / uploaded.
  #
  # @param {DropshipFile} file the file to be added
  # @param {function()} callback called when the file's metadata is persisted
  # @return {DropshipList} this
  addFile: (file, callback) ->
    # TODO(pwnall): store file.json() to indexeddb
    @files[file.uid] = file
    callback()
    @

  # Updates the persisted metadata for a file to reflect changes.
  #
  # @param {DropshipFile} file the file whose state changed
  # @param {function()} callback called when the file's metadata is persisted
  # @return {DropshipList} this
  updateFileState: (file, callback) ->
    # TODO(pwnall): store file.json() to indexeddb
    @

  # Produces a consistent view of the in-progress and completed downloads.
  #
  # @param {function(Array<DropshipFile>)} callback called with a
  #   consistent snapshot of the in-progress and completed download files
  getFiles: (callback) ->
    fileArray = []
    for _, file of @files
      fileArray.push file
    callback fileArray
    @

# Model class that tracks one in-progress or downloaded file.
class DropshipFile
  # @param {Object} options one or more of the attributes below
  # @option options {String} url URL where the file is downloaded from
  # @option options {String} referrer value of the Referer header of the
  #   downloading HTTP request
  # @option options {Number} startedAt the time when the user asked to have the
  #   file downloaded
  # @option options {String} uid identifying string, unique to an extension
  #   instance
  # @option options {Number} size file's size, in bytes; this is only known
  #   after the file's download starts
  # @option options {Number} state file's progress in the download / upload
  #   process
  # @option options {String} errorText user-friendly message describing the
  #   download/upload error
  constructor: (options) ->
    @url = options.url
    @referrer = options.referrer or null
    @startedAt = options.startedAt or Date.now()
    @uid = options.id or DropshipFile.randomUid()
    @size = options.size
    @size = null unless @size or @size is 0
    @errorText = options.errorText or null
    @_state = options.state or DropshipFile.NEW

    @_json = null
    @_basename = null

    @downloadedBytes = 0
    @blob = null

  # @property {String} identifying string, unique to an extension instance
  uid: null

  # @property {String} URL where the file is downloaded from
  url: null

  # @property {String} value of the Referer header when downloading the file
  referrer: null

  # @property {Number} the time when the user asked to have the file
  #   downloaded; this should only be used for relative comparison among
  #   DropshipFile instances on the same extension instance
  startedAt: null

  # @property {Number} the file's size, in bytes
  size: null

  # @property {String} errorText
  errorText: null

  # @return {Number} one of the DropshipFile constants indicating this file's
  #   progress in the download / upload process
  state: -> @_state

  # @return {Object} JSON object that can be passed to the DropshipFile
  #   constructor to build a clone for this file; intended to preserve the
  #   file's contents
  json: ->
    @_json ||=
        url: @url, referrer: @referrer, startedAt: @startedAt, uid: @uid,
        size: @size, state: @_state, errorText: @errorText

  # @return {String} the file's name without the path, query string and
  #   URL fragment
  basename: ->
    return @_basename if @_basename

    basename = @url.substring @url.lastIndexOf('/') + 1
    basename = basename.split('?', 2)[0].split('#', 2)[0]
    @_basename = basename

  # Called when the file started downloading.
  #
  # @param {Number} downloadedBytes should be smaller or equal to totalBytes,
  #   if totalBytes is not null
  # @param {?Number] totalBytes the file's size, if known; null otherwise
  # @return {DropshipFile} this
  setDownloadProgress: (downloadedBytes, totalBytes) ->
    @_state = DropshipFile.DOWNLOADING
    @downloadedBytes = downloadedBytes
    @size = totalBytes if totalBytes
    @

  # Called when the Blob representing the file's content is available.
  #
  # @param {Blob} blob a Blob that has the file's contents
  # @return {DropshipFile} this
  setContents: (blob) ->
    @_state = DropshipFile.DOWNLOADED
    @downloadedBytes = blob.size
    @size = blob.size
    @blob = blob
    @

  # Called when a file's download ends due to an error.
  #
  # @param {Blob} blob a Blob that has the file's contents
  # @return {DropshipFile} this
  setDownloadError: (error) ->
    @_state = DropshipFile.ERROR
    @errorText = "Download error: #{error}"
    @

  # @return {String} a randomly generated unique ID
  @randomUid: ->
    Date.now().toString(36) + Math.random().toString(36).substring(1)

  # state() value before the file has started downloading
  @NEW: 1

  # state() value when the file is being downloaded from its origin
  @DOWNLOADING: 2

  # state() value when the file was downloaded but hasn't started being
  #   uploaded to Dropbox
  @DOWNLOADED: 3

  # state() value when the file is being uploaded to Dropbox
  @UPLOADING: 4

  # state() value when the file was uploaded to Dropbox
  @UPLOADED: 5

  # state() value when the file transfer failed due to an error
  @ERROR: 6

  # state() value when the file transfer was canceled
  @CANCELED: 7


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
    @getPermissions true, =>
      @fileCount += 1
      @files[file.uid] = file

      # NOTE: using Dropbox.Xhr for brevity; for robustness, XMLHttpRequest
      #       should be used directly
      xhr = new Dropbox.Xhr 'GET', file.url
      @xhrs[file.uid] = xhr
      xhr.setResponseType 'blob'
      if file.referrer
        xhr.setHeader 'Referer', file.referrer
      xhr.prepare()
      xhr.xhr.addEventListener 'progress', (event) =>
        @onXhrProgress file, event
      xhr.send (error, blob) => @onXhrResponse file, error, blob
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
      @xhrs[file.uid].xhr.cancel()
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
    return unless @xhrs[file.uid]

    downloadedBytes = event.loaded
    totalBytes = if event.lengthComputable then event.total else null
    file.setDownloadProgress downloadedBytes, totalBytes
    @onStateChange.dispatch file

  # Removes one of the files tracked for download.
  #
  # @private Called by cancelFile and onXhrResponse.
  #
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


# Manages the process of uploading files to Dropbox.
class UploadController
  # @param {Dropbox.Chrome} dropboxChrome Chrome extension-friendly wraper for
  #   the Dropbox client to be used for uploading
  constructor: (@dropboxChrome) ->
    @files = {}


class EventPageController
  # @param {Dropbox.Chrome} dropboxChrome
  constructor: (@dropboxChrome) ->
    chrome.browserAction.onClicked.addListener => @onBrowserAction()
    chrome.contextMenus.onClicked.addListener (data) => @onContextMenu data
    chrome.extension.onMessage.addListener => @onMessage
    chrome.runtime.onInstalled.addListener =>
      @onInstall()
      @onStart()
    chrome.runtime.onStartup.addListener => @onStart()

    @dropboxChrome.onClient.addListener (client) =>
      client.onAuthStateChange.addListener => @onDropboxAuthChange client
      client.onError.addListener (error) => @onDropboxError client, error

    @downloadController = new DownloadController
    @downloadController.onPermissionDenied.addListener =>
      @errorNotice 'Download canceled due to denied permissions'
    @downloadController.onStateChange.addListener (file) =>
      @onDownloadStateChange file

    @uploadController = new UploadController @dropboxChrome

    @fileList = new DropshipList

  # Called by Chrome when the user installs the extension.
  onInstall: ->
    chrome.contextMenus.create
        id: 'download', title: 'Upload to Dropbox', enabled: false,
        contexts: ['page', 'frame', 'link', 'image', 'video', 'audio']

  # Called by Chrome when the user installs the extension or starts Chrome.
  onStart: ->
    @dropboxChrome.client (client) =>
      @onDropboxAuthChange client

  # Called by Chrome when the user clicks the browser action.
  onBrowserAction: ->
    @dropboxChrome.client (client) ->
      if client.isAuthenticated()
        # Chrome did not show up the popup for some reason. Do it here.
        chrome.tabs.create url: 'html/popup.html', active: true, pinned: false

      credentials = client.credentials()
      if credentials.authState
        # The user clicked our button while we're signing him/her into Dropbox.
        # We can consider that the sign-up failed and try again. Most likely,
        # the user closed the Dropbox authorization tab.
        client.reset()

      # Start the sign-in process.
      client.authenticate (error) ->
        client.reset() if error

  # Called by Chrome when the user clicks the extension's context menu item.
  onContextMenu: (clickData) ->
    url = null
    referrer = null
    if clickData.srCUrl or clickData.linkUrl
      if clickData.mediaType
        url = clickData.srcUrl or clickData.linkUrl
      else
        url = clickData.linkUrl or clickData.srcUrl
      referrer = clickData.frameUrl or clickData.pageUrl
    else if clickData.frameUrl
      url = clickData.frameUrl
      referrer = clickData.pageUrl
    else if clickData.pageUrl
      url = clickData.pageUrl
      # TODO(pwnall): see if we can get the page referrer
      referrer = clickData.pageUrl
    else
      # This should never happen. At the very least, pageUrl should always be
      # set. If it does happen, there needs to be some sort of error message
      # here.
      return

    file = new DropshipFile url: url, referrer: referrer
    @downloadController.addFile file, =>
      @fileList.addFile file, =>
        chrome.extension.sendMessage type: 'update_files'

  # Called when the Dropbox authentication state changes.
  onDropboxAuthChange: (client) ->
    # Update the badge to reflect the current authentication state.
    if client.isAuthenticated()
      chrome.contextMenus.update 'download', enabled: true
      chrome.browserAction.setPopup popup: 'html/popup.html'
      chrome.browserAction.setTitle title: "Signed in"
      chrome.browserAction.setBadgeText text: ''
    else
      chrome.contextMenus.update 'download', enabled: false
      chrome.browserAction.setPopup popup: ''

      credentials = client.credentials()
      if credentials.authState
        chrome.browserAction.setTitle title: 'Signing in...'
        chrome.browserAction.setBadgeText text: '...'
        chrome.browserAction.setBadgeBackgroundColor color: '#DFBF20'
      else
        chrome.browserAction.setTitle title: 'Click to sign into Dropbox'
        chrome.browserAction.setBadgeText text: '?'
        chrome.browserAction.setBadgeBackgroundColor color: '#DF2020'

  # Called when the Dropbox API server returns an error.
  onDropboxError: (client, error) ->
    @errorNotice "Something went wrong while talking to Dropbox: #{error}"

  # Called when a file's download state changes.
  onDownloadStateChange: (file) ->
    if file.state() is DropshipFile.DOWNLOADED
      # TODO(pwnall): set up Dropbox upload
      null

    chrome.extension.sendMessage type: 'update_file', fileUid: file.uid

  # Shows a desktop notification informing the user that an error occurred.
  errorNotice: (errorText) ->
    webkitNotifications.createNotification 'images/icon48.png',
        'Download to Dropbox', errorText


dropboxChrome = new Dropbox.Chrome(
  key: 'fOAYMWHVRVA=|pHQC3wPkdQ718FleqazY8eZQmxyhJ5n4G5++PXDYBg==',
  sandbox: true)
window.controller = new EventPageController dropboxChrome
