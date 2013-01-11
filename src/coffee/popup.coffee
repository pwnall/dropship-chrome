class DownloadsView
  constructor: (@root) ->
    @$root = $ @root
    @$userInfo = $ '#dropbox-info', @$root
    @$userName = $ '#dropbox-name', @$userInfo
    @$userEmail = $ '#dropbox-email', @$userInfo
    @$signoutButton = $ '#dropbox-signout', @$userInfo
    @$signoutButton.click (event) => @onSignoutClick event
    @$closeButton = $ '#close-window-button', @$root
    @$closeButton.click (event) => @onCloseClick event
    @$maximizeButton = $ '#maximize-window-button', @$root
    @$maximizeButton.click (event) => @onMaximizeClick event
    @$fileList = $ '#file-list', @$root
    @fileTemplate = $('#file-item-template', @$root).text()

    chrome.extension.onMessage.addListener (message) => @onMessage message

    @files = []
    @$fileDoms = []
    @fileIndexes = {}

    @reloadUserInfo()
    @updateFileList()

  # Updates the Dropbox user information in the view.
  reloadUserInfo: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.dropboxChrome.userInfo (userInfo) =>
        @$userInfo.removeClass 'hidden'
        @$userName.text userInfo.name
        @$userEmail.text userInfo.email
    @

  # Updates the entire file list view.
  updateFileList: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.fileList.getFiles (fileMap) =>
        files = (file for own uid, file of fileMap)
        # (b, a) is an easy hack to switch from ascending to descending sort
        files.sort (b, a) ->
          if a.startedAt != b.startedAt
            a.startedAt - b.startedAt
          else
            a.uid.localeCompare b.uid
        @files = files
        @fileIndexes = {}
        @fileIndexes[file.uid] = i for file, i in @files

        @renderFileList()
    @

  # Updates one file in the view.
  updateFile: (fileUid) ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.fileList.getFiles (fileMap) =>
        unless fileUid of @fileIndexes
          return @updateFileList()
        fileIndex = @fileIndexes[fileUid]
        unless @files[fileIndex].uid is fileUid
          return @updateFileList()

        file = fileMap[fileUid]
        @files[fileIndex] = file
        @updateFileDom @$fileDoms[fileIndex], file
    @

  # Redraws the entire file list.
  renderFileList: ->
    @$fileList.empty()
    fileDoms = []
    for file in @files
      $fileDom = $ @fileTemplate
      @updateFileDom $fileDom, file
      @$fileList.append $fileDom
      @wireFileDom $fileDom, file
      fileDoms.push $fileDom
    @$fileDoms = fileDoms
    @

  # Sets up event listeners for the buttons in a file's view.
  wireFileDom: ($fileDom, file) ->
    $('.file-item-retry', $fileDom).click (event) =>
      @onRetryClick event, file
    $('.file-item-cancel', $fileDom).click (event) =>
      @onCancelClick event, file
    $('.file-item-hide', $fileDom).click (event) =>
      @onHideClick event, file
    @

  # Updates the DOM for a file entry to reflect the file's current state.
  updateFileDom: ($fileDom, file) ->
    # Status.
    switch file.state()
      when DropshipFile.NEW, DropshipFile.DOWNLOADING, DropshipFile.DOWNLOADED
        iconClass = 'icon-spinner icon-spin file-status-inprogress'
        iconTitle = 'Downloading'
      when DropshipFile.SAVING, DropshipFile.SAVED
        iconClass = 'icon-spinner icon-spin file-status-inprogress'
        iconTitle = 'Preparing to upload'
      when DropshipFile.UPLOADING
        iconClass = 'icon-spinner icon-spin file-status-inprogress'
        iconTitle = 'Saving to Dropbox'
      when DropshipFile.UPLOADED
        iconClass = 'icon-ok file-status-done'
        iconTitle = 'Saved to Dropbox'
      when DropshipFile.CANCELED
        iconClass = 'icon-ban-circle file-status-canceled'
        iconTitle = 'Canceled'
      when DropshipFile.ERROR
        iconClass = 'icon-exclamation-sign file-status-error'
        iconTitle = 'Something went wrong'
    $statusDom = $ '.file-item-status i', $fileDom
    # Changing the <i>'s attributes resets icon animations, so blind writes are
    # bad.
    if $statusDom.attr('class') isnt iconClass
      $statusDom.attr 'class', iconClass
    if $statusDom.attr('title') isnt iconTitle
      $statusDom.attr 'title', iconTitle

    # Metadata.
    $fileDom.attr 'data-file-uid', file.uid
    $('.file-name', $fileDom).text file.basename()
    $('.file-item-link', $fileDom).text(file.url).attr 'href', file.url
    if file.size
      $('.file-size', $fileDom).text(humanize.filesize(file.size)).
          attr 'title', humanize.numberFormat(file.size, 0)

    # Progress bars.
    if file.size
      $('progress', $fileDom).attr 'max', file.size
    else
      $('progress', $fileDom).removeAttr 'max'

    $('.file-down-progress', $fileDom).attr 'value', file.downloadedBytes()
    if file.size
      $('.file-down-wrapper', $fileDom).attr 'title',
          "#{humanize.numberFormat(file.downloadedBytes(), 0)} / " +
          "#{humanize.numberFormat(file.size, 0)} bytes downloaded"
    else
      $('.file-down-wrapper', $fileDom).attr 'title',
          "#{humanize.numberFormat(file.downloadedBytes(), 0)} bytes downloaded"

    $('.file-save-progress', $fileDom).attr 'value', file.savedBytes()
    if file.state() >= DropshipFile.SAVING
      $('.file-save-wrapper', $fileDom).attr 'title',
          "#{humanize.numberFormat(file.savedBytes(), 0)} / " +
          "#{humanize.numberFormat(file.size, 0)} bytes saved to disk"
    else
      $('.file-save-wrapper', $fileDom).attr 'title', 'waiting for download'

    $('.file-up-progress', $fileDom).attr 'value', file.uploadedBytes()
    if file.state() >= DropshipFile.UPLOADING
      $('.file-up-wrapper', $fileDom).attr 'title',
          "#{humanize.numberFormat(file.uploadedBytes(), 0)} / " +
          "#{humanize.numberFormat(file.size, 0)} bytes uploaded to dropbox"
    else
      $('.file-up-wrapper', $fileDom).attr 'title', 'waiting for save'

    if file.state() < DropshipFile.DOWNLOADING or
       file.state() >= DropshipFile.UPLOADED
      $('.file-item-progress', $fileDom).addClass 'hidden'
    else
      $('.file-item-progress', $fileDom).removeClass 'hidden'

    # Error display.
    if file.state() >= DropshipFile.ERROR
      $('.file-item-error', $fileDom).removeClass 'hidden'
      $('.file-error-text', $fileDom).text file.errorText
    else
      $('.file-item-error', $fileDom).addClass 'hidden'

    # Actions.
    if file.canBeRetried()
      $('.file-item-retry', $fileDom).removeClass('hidden').
          removeAttr 'disabled'
    else
      $('.file-item-retry', $fileDom).addClass 'hidden'
    if file.canBeCanceled()
      $('.file-item-cancel', $fileDom).removeClass('hidden').
          removeAttr 'disabled'
    else
      $('.file-item-cancel', $fileDom).addClass 'hidden'
    if file.canBeHidden()
      $('.file-item-hide', $fileDom).removeClass('hidden').
          removeAttr 'disabled'
    else
      $('.file-item-hide', $fileDom).addClass 'hidden'
    @

  # Called when the user clicks on a file's Retry button.
  onRetryClick: (event, file) ->
    event.preventDefault()
    $(event.target).attr 'disabled', true
    chrome.runtime.getBackgroundPage (eventPage) ->
      eventPage.controller.retryFile file, -> null
    false

  # Called when the user clicks on a file's Cancel button.
  onCancelClick: (event, file) ->
    event.preventDefault()
    $(event.target).attr 'disabled', true
    chrome.runtime.getBackgroundPage (eventPage) ->
      eventPage.controller.cancelFile file, -> null
    false

  # Called when the user clicks on a file's Hide button.
  onHideClick: (event, file) ->
    event.preventDefault()
    $(event.target).attr 'disabled', true
    chrome.runtime.getBackgroundPage (eventPage) ->
      eventPage.controller.removeFile file, -> null
    false

  # Called when the user clicks on the 'Sign out' button.
  onSignoutClick: (event) ->
    @$signoutButton.attr 'disabled', true
    event.preventDefault()
    window.close()
    chrome.runtime.getBackgroundPage (eventPage) ->
      eventPage.controller.signOut => null
    false

  # Called when the user clicks on the window close button.
  onCloseClick: (event) ->
    window.close()

  # Called when the user clicks on the window maximize button.
  onMaximizeClick: (event) ->
    chrome.tabs.create url: 'html/popup.html', active: true, pinned: false
    window.close()

  # Called when a Chrome extension internal message is received.
  onMessage: (message) ->
    switch message.notice
      when 'update_file'
        @updateFile message.fileUid
      when 'update_files'
        @updateFileList()

$ ->
  # The view is in the global namespace to facilitate debugging.
  window.view = new DownloadsView document.body
