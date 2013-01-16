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
    @fileList.onStateChange.addListener (file) =>
      @onFileStateChange file
    @restoreFiles -> null

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
    if clickData.srcUrl or clickData.linkUrl
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

    file = new DropshipFile url: url, headers: { Referer: referrer }
    @downloadController.addFile file, =>
      @fileList.addFile file, =>
        chrome.extension.sendMessage notice: 'update_files'

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

  # Resumes the ongoing downloads / uploads.
  restoreFiles: (callback) ->
    @fileList.getFiles (files) =>
      barrierCount = 1
      barrier = ->
        barrierCount -= 1
        callback() if barrierCount is 0

      for own uid, file of files
        switch file.state()
          when DropshipFile.UPLOADED, DropshipFile.ERROR, DropshipFile.CANCELED
            # Nothing to do.
          else
            barrierCount += 1
            @fileList.getFileContents file, (error, blob) =>
              if blob
                file.blob = blob
                @uploadController.addFile file, barrier
              else
                @downloadController.addFile file, barrier
      barrier()

  # Called when the user asks to have a file download / upload canceled.
  cancelFile: (file, callback) ->
    switch file.state()
      when DropshipFile.DOWNLOADING
        @downloadController.cancelFile file, =>
          file.setCanceled()
          @fileList.updateFileState file, (error) =>
            chrome.extension.sendMessage(
                notice: 'update_file', fileUid: file.uid)
            callback()
      when DropshipFile.SAVING
        file.setCanceled()
        @fileList.cancelFileContents file, =>
          @fileList.updateFileState file, (error) =>
            chrome.extension.sendMessage(
                notice: 'update_file', fileUid: file.uid)
            callback()
      when DropshipFile.UPLOADING
        @uploadController.cancelFile file, =>
          file.setCanceled()
          @fileList.updateFileState file, (error) =>
            chrome.extension.sendMessage(
                notice: 'update_file', fileUid: file.uid)
            callback()
      else  # The file got in a different state.
        callback()
    @

  # Called when the user asks to have a file's info removed from the list.
  removeFile: (file, callback) ->
    switch file.state()
      when DropshipFile.UPLOADED, DropshipFile.ERROR, DropshipFile.CANCELED
        @fileList.removeFileState file, ->
          chrome.extension.sendMessage notice: 'update_files'
          callback()
      else  # The file got in a different state.
        callback()
    @

  # Called when the user asks to have a download / upload re-attempted.
  retryFile: (file, callback) ->
    switch file.state()
      when DropshipFile.UPLOADED, DropshipFile.ERROR, DropshipFile.CANCELED
        @fileList.getFileContents file, (error, blob) =>
          if blob
            file.blob = blob
            @uploadController.addFile file, callback
          else
            @downloadController.addFile file, callback
      else  # The file got in a different state.
        callback()
    @

  # Called when the user asks to have completed transfers bulk-removed.
  #
  # This works like calling removeFiles on the files, but does the removing in
  # one IndexedDB transaction and requires a single DOM rebuild in the popup.
  removeUploadedFiles: (callback) ->
    @fileList.getFiles (files) =>
      uploadedFiles = []
      for uid, file of files
        if file.state() is DropshipFile.UPLOADED
          uploadedFiles.push file

      @fileList.removeFileStates uploadedFiles, ->
        chrome.extension.sendMessage notice: 'update_files'
        callback()
    @


  # Called when the user wishes to sign out of Dropbox.
  signOut: (callback) ->
    @fileList.getFiles (files) =>
      # After all transfers are stopped, sign out and delete everything.
      barrierCount = 1
      barrier = =>
        barrierCount -= 1
        return if barrierCount isnt 0
        dropboxChrome.signOut =>
          @fileList.removeDb =>
            chrome.extension.sendMessage notice: 'reset_files'
            callback()

      # Stop all transfers.
      for own uid, file of files
        switch file.state()
          when DropshipFile.DOWNLOADING
            barrierCount += 1
            @downloadController.removeFile file, => barrier()
          when DropshipFile.UPLOADING
            barrierCount += 1
            @uploadController.removeFile file, => barrier()
          when DropshipFile.SAVING
            barrierCount += 1
            @fileController.cancelSetFileContents file, => barrier()
      barrier()

  # Called when the Dropbox API server returns an error.
  onDropboxError: (client, error) ->
    @errorNotice "Something went wrong while talking to Dropbox: #{error}"

  # Called when a file's state changes.
  onFileStateChange: (file) ->
    @fileList.updateFileState file, (error) =>
      return if error
      chrome.extension.sendMessage notice: 'update_file', fileUid: file.uid

      switch file.state()
        when DropshipFile.DOWNLOADED
          @fileList.setFileContents file, file.blob, (error) =>
            if error
              chrome.extension.sendMessage(
                  notice: 'update_file', fileUid: file.uid)
        when DropshipFile.SAVED
          @uploadController.addFile file, =>
            chrome.extension.sendMessage(
                notice: 'update_file', fileUid: file.uid)
        when DropshipFile.UPLOADED
          @fileList.removeFileContents file, (error) -> null

  # Shows a desktop notification informing the user that an error occurred.
  errorNotice: (errorText) ->
    webkitNotifications.createNotification 'images/icon48.png',
        'Download to Dropbox', errorText


dropboxChrome = new Dropbox.Chrome(
  key: 'fOAYMWHVRVA=|pHQC3wPkdQ718FleqazY8eZQmxyhJ5n4G5++PXDYBg==',
  sandbox: true)
window.controller = new EventPageController dropboxChrome
