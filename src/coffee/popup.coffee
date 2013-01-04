class DownloadsView
  constructor: (@root) ->
    @$root = $ @root
    @$userInfo = $ '#dropbox-info', @$root
    @$userName = $ '#dropbox-name', @$root
    @$userEmail = $ '#dropbox-email', @$root
    @$fileList = $ '#file-list', @$root
    @fileTemplate = $('#file-item-template', @$root).text()

    chrome.extension.onMessage.addListener (message) => @onMessage message

    @reloadUserInfo()
    @updateFileList()

  # Updates the Dropbox user information in the view.
  reloadUserInfo: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.dropboxChrome.userInfo (userInfo) =>
        @$userInfo.removeClass 'hidden'
        @$userName.text userInfo.name
        @$userEmail.text userInfo.email

  # Updates the entire file list view.
  updateFileList: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.fileList.getFiles (files) =>
        files.sort (a, b) ->
          if a.startedAt != b.startedAt
            a.startedAt - b.startedAt
          else
            a.uid.localeCompare b.uid
        @files = files
        @renderFileList()

  # Redraws the entire file list.
  renderFileList: ->
    @$fileList.empty()
    for _, file of @files
      $fileDom = $ @fileTemplate
      @updateFileDom $fileDom, file
      @$fileList.append $fileDom
    @

  updateFileDom: ($fileDom, file) ->
    $('.file-name', $fileDom).text file.basename()
    if file.size
      $('.file-progress', $fileDom).attr 'max', file.size
      $('.file-progress', $fileDom).attr 'value', file.downloadedBytes
      percentage = Math.floor (100 * file.downloadedBytes) / file.size
      $('.file-progress-label', $fileDom).text "#{percentage}%"
    else
      $('.file-progress', $fileDom).attr 'max', 1
      $('.file-progress', $fileDom).attr 'value', 0
      $('.file-progress-label').text file.downloadedBytes
    $fileDom

  # Called when a Chrome extension internal message is received.
  onMessage: (message) ->
    switch message.notice
      when 'update_file'
        @
      when 'update_files'
        @updateFileList()


$ ->
  window.view = new DownloadsView document.body
