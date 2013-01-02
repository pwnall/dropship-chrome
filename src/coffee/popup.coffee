class DownloadsView
  constructor: (@root) ->
    @$root = $ @root
    @$userInfo = $ '#dropbox-info', @$root
    @$userName = $ '#dropbox-name', @$root
    @$userEmail = $ '#dropbox-email', @$root
    @reloadUserInfo()

  reloadUserInfo: ->
    chrome.extension.sendMessage command: 'user_info', (response) =>
      @$userInfo.removeClass 'hidden'
      @$userName.text response.name
      @$userEmail.text response.email

new DownloadView document.body
