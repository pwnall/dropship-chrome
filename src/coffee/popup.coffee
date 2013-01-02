class DownloadsView
  constructor: (@root) ->
    @$root = $ @root
    @$userInfo = $ '#dropbox-info', @$root
    @$userName = $ '#dropbox-name', @$root
    @$userEmail = $ '#dropbox-email', @$root
    @reloadUserInfo()

  reloadUserInfo: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.dropboxChrome.userInfo (userInfo) =>
        @$userInfo.removeClass 'hidden'
        @$userName.text userInfo.name
        @$userEmail.text userInfo.email

$ ->
  window.view = new DownloadsView document.body
