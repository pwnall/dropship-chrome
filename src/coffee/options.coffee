class OptionsView
  constructor: (@root) ->
    @$root = $ @root
    @$userInfo = $ '#dropbox-info', @$root
    @$userName = $ '#dropbox-name', @$userInfo
    @$userEmail = $ '#dropbox-email', @$userInfo
    @$signoutButton = $ '#dropbox-signout', @$userInfo
    @$signoutButton.click (event) => @onSignoutClick event
    @$navItems = $ '#nav-list .nav-list-item', @$root
    @$navLinks = $ '#nav-list .nav-list-item a', @$root
    @$pageContainer = $ '#page-container', @$root
    @$pages = $ '#page-container article', @$root

    @updateVisiblePage()
    @$pageContainer.removeClass 'hidden'
    window.addEventListener 'hashchange', (event) => @updateVisiblePage()

    chrome.extension.onMessage.addListener (message) => @onMessage message

    @reloadUserInfo()

  # Changes the markup classes to show the page identified by the hashtag.
  updateVisiblePage: ->
    pageId = window.location.hash.substring(1) or @defaultPage
    @$pages.each (index, page) ->
      $page = $ page
      $page.toggleClass 'hidden', $page.attr('id') isnt pageId
      console.log $page
    pageHash = '#' + pageId
    @$navItems.each (index, navItem) =>
      $navItem = $ navItem
      $navLink = $ @$navLinks[index]
      $navItem.toggleClass 'current', $navLink.attr('href') is pageHash

  # Updates the Dropbox user information in the view.
  reloadUserInfo: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.dropboxChrome.userInfo (userInfo) =>
        @$userInfo.removeClass 'hidden'
        @$userName.text userInfo.name
        @$userEmail.text userInfo.email
    @

  # The page that is shown when the options view is shown.
  defaultPage: 'download-options'

$ ->
  window.view = new OptionsView document.body

