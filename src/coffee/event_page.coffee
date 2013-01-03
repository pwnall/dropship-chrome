_client = null

#
class Dropbox.Chrome
  # @param {Object} options to be passed to the Dropbox API client; the object
  #     should have the properties 'key' and 'sandbox'
  constructor: (@clientOptions) ->
    @_client = null
    @_userInfo = null
    @onClient = new Dropbox.EventSource

  # @property {Dropbox.EventSource<Dropbox.Client>} triggered when a new
  #   Dropbox.Client instance is created; can be used to attach listeners to
  #   the client
  onClient: null

  # Produces a properly set up Dropbox API client.
  #
  # @param {function(Dropbox.Client)} callback called with the Dropbox.Client
  #   instance
  # @return {null} null
  client: (callback) ->
    if @_client
      callback @_client
      return null

    authDriver = new Dropbox.Drivers.ChromeExtension(
        receiverPath: 'html/chrome_oauth_receiver.html')
    authDriver.loadCredentials (credentials) =>
      unless credentials && credentials.token && credentials.tokenSecret
        # Missing or corrupted credentials.
        credentials = @clientOptions
      @_client = new Dropbox.Client credentials
      @_client.authDriver authDriver
      @onClient.dispatch @_client
      callback @_client
    null

  # Returns a (potentially cached) version of the Dropbox user's information.
  userInfo: (callback) ->
    if @_userInfo
      callback @_userInfo
      return null

    chrome.storage.local.get 'dropbox_js_userinfo', (items) =>
      if items && items.dropbox_js_userinfo
        try
          @_userInfo = Dropbox.UserInfo.parse items.dropbox_js_userinfo
          return callback @_userInfo
        catch Error
          # There was a parsing error. Let the control flow fall.

      @client (client) =>
        client.getUserInfo (error, userInfo) =>
          return if error
          @_userInfo = userInfo
          chrome.storage.local.set dropbox_js_userinfo: userInfo.json(), =>
            callback @_userInfo

# Manages the process of downloading files from their origin site.
class DownloadController
  constructor: ->
    @fileCount = 0
    @files = {}
    @xhrs = {}
    @onPermissionDenied = new Dropbox.EventSource

  # @property {Dropbox.EventSource<null>} non-cancelable events fired when the
  #   user denies the temporary permissions needed to download a file;
  #   listeners should inform the user that their download was canceled
  onPermissionDenied: null

  # Adds a file to the list of files to be downloaded.
  #
  # @param {DropshipFile} file descriptor for the file to be downloaded
  # @param {function()} callback called when the file is successfully added for
  #   download; not called if the download is aborted due to permission issues
  # @return this
  addFile: (file, callback) ->
    @getPermissions true, ->
      @fileCount += 1
      @files[file.id] = file

      # NOTE: using Dropbox.Xhr for brevity; for robustness, XMLHttpRequest
      #       should be used directly
      xhr = new Dropbox.Xhr 'GET', file.url
      @xhrs[file.id] = xhr
      xhr.setResponseType 'blob'
      if file.referrer
        xhr.setHeader 'Referer', file.referrer
      xhr.prepare()
      xhr.send (error, blob) => @onXhrResponse file, error, blob
      callback()

  # Cancels the download process for a file.
  cancelFile: (file, callback) ->


  # @param {DropshipFile} file
  # @param {?Dropbox.ApiError} error set if the XHR went wrong
  # @param {?Blob} blob the downloaded file
  onXhrResponse: (file, error, blob) ->
    #
    return unless @xhrs[file.id]


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
      chrome.permissions.contains origins: '<any_url>', (allowed) =>
        if allowed
          return callback()
        chrome.permissions.request origins: '<any_url>', (granted) =>
          if granted
            return callback()
          @onPermissionDenied.dispatch null
    else
      unless @fileCount is 0
        return callback()
      chrome.permissions.contains origins: '<any_url>', (allowed) ->
        unless allowed
          return callback()
        chrome.permissions.remove origins: '<any_url>', -> callback()
    @

            # TODO(pwnall): explain to the user that we can't download without
            #               permissions and ask them to try again


# Manages the process of uploading files to Dropbox.
class UploadController
  # @param {Dropbox.Client} client the Dropbox client to be used for uploading
  constructor: (@client) ->
    @files = {}

# Model class that tracks all the in-progress and completed downloads.
class DropshipList
  constructor: ->


# Model class that tracks one in-progress or downloaded file.
class DropshipFile
  # @param {Object} options one or more of the attributes below
  # @option options {String} url
  # @option options {String} referrer
  # @option options {String}
  constructor: (options) ->
    @url = options.url
    @referrer = options.referrer or null
    @uid = options.id or DropshipFile.randomUid()
    @_json = null

  # @property {String} identifying string, unique to an extension installation
  uid: null

  # @property {String} the URL where the file is downloaded from
  url: null

  # @return {Object}
  json: ->
    @_json ||= url: @url, referrer: @referrer, uid: @uid

  # @return {String} a randomly generated unique ID
  @randomUid: ->
    Date.now().toString(36) + Math.random().toString(36).substring(1)


class EventPageController
  # @param {Dropbox.Chrome} dropboxChrome
  constructor: (@dropboxChrome) ->
    chrome.browserAction.onClicked.addListener => @onBrowserAction()
    chrome.contextMenu.onClicked.addListener (data) => @onContextMenu data
    chrome.extension.onMessage.addListener => @onMessage
    chrome.runtime.onInstalled.addListener => @onStart()
    chrome.runtime.onStartup.addListener => @onStart()
    @dropboxChrome.onClient.addListener (client) =>
      client.onAuthStateChange.addListener => @onDropboxAuthChange client
      client.onError.addListener (error) => @onDropboxError client, error

  # Called by Chrome when the user installs the extension.
  onInstall: ->
    chrome.contextMenus.create
        id: 'download', title: 'Upload to Dropbox',
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

    if clickData.mediaType
      url = clickData.srcUrl or clickData.linkUrl or clickData.frameUrl or
            clickData.pageUrl
    else
      url = clickData.linkUrl or clickData.srcUrl or clickData.frameUrl or
            clickData.pageUrl
    unless url
      # This should never happen. At the very least, pageUrl should always be
      # set. If it does happen, there needs to be some sort of error message
      # here.
      return

  # Called when the Dropbox authentication state changes.
  onDropboxAuthChange: (client) ->
    # Update the badge to reflect the current authentication state.
    if client.isAuthenticated()
      chrome.browserAction.setPopup popup: 'html/popup.html'
      chrome.browserAction.setTitle title: "Signed in"
      chrome.browserAction.setBadgeText text: ''
    else
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

  # Shows a desktop notification informing the user that an error occurred.
  errorNotice: (errorText) ->
    webkitNotifications.createNotification 'images/icon48.png',
        'Download to Dropbox', errorText


dropboxChrome = new Dropbox.Chrome(
  key: 'fOAYMWHVRVA=|pHQC3wPkdQ718FleqazY8eZQmxyhJ5n4G5++PXDYBg==',
  sandbox: true)

window.controller = new EventPageController dropboxChrome
