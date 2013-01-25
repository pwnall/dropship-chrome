# Renders the current options.
class OptionsView
  constructor: (@root) ->
    @$root = $ @root
    @$userInfo = $ '#dropbox-info', @$root
    @$userName = $ '#dropbox-name', @$userInfo
    @$userEmail = $ '#dropbox-email', @$userInfo
    @$signoutButton = $ '#dropbox-signout', @$userInfo
    @$signoutButton.on 'click', (event) => @onSignoutClick event
    @$navItems = $ '#nav-list .nav-list-item', @$root
    @$navLinks = $ '#nav-list .nav-list-item a', @$root
    @$pageContainer = $ '#page-container', @$root
    @$pages = $ '#page-container article', @$root

    @$downloadSiteFolder = $ '#download-site-folder', @$root
    @$downloadSiteFolder.on 'change', => @onChange()
    @$downloadDateFolder = $ '#download-date-folder', @$root
    @$downloadDateFolder.on 'change', => @onChange()
    @$downloadFolderSample = $ '#download-folder-sample', @$root

    @updateData =>
      @updateVisiblePage()
      @$pageContainer.removeClass 'hidden'
      window.addEventListener 'hashchange', (event) => @updateVisiblePage()

    chrome.extension.onMessage.addListener (message) => @onMessage message

    @reloadUserInfo()

  # Updates the DOM with the current settings.
  #
  # @param {function()} callback called when the DOM reflects the current
  #   settings
  # @return {OptionsView} this
  updateData: (callback) ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      options = eventPage.controller.options
      options.items (items) =>
        @$downloadSiteFolder.prop 'checked', items.downloadSiteFolder
        @$downloadDateFolder.prop 'checked', items.downloadDateFolder
        @$downloadFolderSample.text options.sampleDownloadFolder(items)

        callback()
    @

  # Called when one of the settings on the page changes.
  onChange: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      options = eventPage.controller.options
      options.items (items) =>
        items.downloadSiteFolder = @$downloadSiteFolder.prop 'checked'
        items.downloadDateFolder = @$downloadDateFolder.prop 'checked'
        @$downloadFolderSample.text options.sampleDownloadFolder(items)

        options.setItems items, -> null
    @

  # Changes the markup classes to show the page identified by the hashtag.
  #
  # @return {OptionsView} this
  updateVisiblePage: ->
    pageId = window.location.hash.substring(1) or @defaultPage
    @$pages.each (index, page) ->
      $page = $ page
      $page.toggleClass 'hidden', $page.attr('id') isnt pageId
    pageHash = '#' + pageId
    @$navItems.each (index, navItem) =>
      $navItem = $ navItem
      $navLink = $ @$navLinks[index]
      $navItem.toggleClass 'current', $navLink.attr('href') is pageHash
    @

  # Updates the preferences to reflect a
  onDownloadFormChange: ->

  # Updates the Dropbox user information in the view.
  reloadUserInfo: ->
    chrome.runtime.getBackgroundPage (eventPage) =>
      eventPage.controller.dropboxChrome.userInfo (userInfo) =>
        @$userInfo.removeClass 'hidden'
        @$userName.text userInfo.name
        @$userEmail.text userInfo.email
    @

  # The page that is shown when the options view is shown.
  defaultPage: 'download-flags'

$ ->
  window.view = new OptionsView document.body

