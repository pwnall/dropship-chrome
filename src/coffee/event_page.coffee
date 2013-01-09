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
      @onFileStateChange file

    @uploadController = new UploadController @dropboxChrome
    @uploadController.onStateChange.addListener (file) =>
      @onFileStateChange file

    @fileList = new DropshipList
    @fileList.onDbError.addListener (errorText) =>
      @errorNotice errorText

  # Called by Chrome when the user installs the extension.
  onInstall: ->
    chrome.contextMenus.create
        id: 'download', title: 'Upload to Dropbox', enabled: false,
        contexts: ['page', 'frame', 'link', 'image', 'video', 'audio']

    # Create or upgrade the database.
    @fileList.db -> null

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

  # Called when a file's state changes.
  onFileStateChange: (file) ->
    @fileList.updateFileState file, (error) =>
      return if error
      chrome.extension.sendMessage type: 'update_file', fileUid: file.uid

      switch file.state()
        when DropshipFile.DOWNLOADED
          @fileList.setFileContents file, file.blob, (error) =>
            if error
              chrome.extension.sendMessage(
                  type: 'update_file', fileUid: file.uid)
              return

            @uploadController.addFile file, =>
              chrome.extension.sendMessage(
                  type: 'update_file', fileUid: file.uid)
        when DropshipFile.UPLOADED
          @fileList.removeFileContents file, (error) =>
            chrome.extension.sendMessage type: 'update_file', fileUid: file.uid

  # Shows a desktop notification informing the user that an error occurred.
  errorNotice: (errorText) ->
    webkitNotifications.createNotification 'images/icon48.png',
        'Download to Dropbox', errorText


dropboxChrome = new Dropbox.Chrome(
  key: 'fOAYMWHVRVA=|pHQC3wPkdQ718FleqazY8eZQmxyhJ5n4G5++PXDYBg==',
  sandbox: true)
window.controller = new EventPageController dropboxChrome
