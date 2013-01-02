_client = null

class DropboxChrome
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

    chrome.storage.get 'dropbox_js_userinfo', (items) =>
      if items && items.dropbox_js_userinfo
        @_userInfo = Dropbox.UserInfo.parse items.dropbox_js_userinfo
        return callback @_userInfo

      @client (client) =>
        client.getUserInfo (error, userInfo) =>
          return if error
          @_userInfo = userInfo
          chrome.storage.set dropbox_js_userinfo: userInfo, =>
            callback @_userInfo



class EventPageController
  constructor: (@dropboxChrome) ->
    chrome.browserAction.onClicked.addListener => @onBrowserAction()
    chrome.runtime.onInstalled.addListener => @onStart()
    chrome.runtime.onStartup.addListener => @onStart()
    @dropboxChrome.onClient.addListener (client) =>
      client.onAuthStateChange.addListener => @onDropboxAuthChange client
      client.onError.addListener (error) => @onDropboxError client, error

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

  # Called by Chrome when the user installs the extension or starts Chrome.
  onStart: ->
    @dropboxChrome.client (client) =>
      @onDropboxAuthChange client

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


dropboxChrome = new DropboxChrome(
  key: 'fOAYMWHVRVA=|pHQC3wPkdQ718FleqazY8eZQmxyhJ5n4G5++PXDYBg==',
  sandbox: true)

# Exporting the controller for easy debugging.
window.controller = new EventPageController dropboxChrome
