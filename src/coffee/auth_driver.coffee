# OAuth driver specialized for Chrome extensions.
class Dropbox.Drivers.ChromeExtension
  # @param {?Object} options the settings below
  # @option {String} receiverPath the path of page that receives the /authorize
  #   redirect and performs the postMessage; the path should be relative to the
  #   extension folder; by default, is 'html/chrome_oauth_receiver.html'
  constructor: (options) ->
    receiverPath = options.receiverPath || 'html/chrome_oauth_receiver.html'
    @receiverUrl = chrome.extension.getURL receiverPath
    @tokenRe = new RegExp "(#|\\?|&)oauth_token=([^&#]+)(&|#|$)"

  # Saves token information when appropriate.
  onAuthStateChange: (client, callback) ->
    switch client.authState
      when Dropbox.Client.DONE
        @storeCredentials client.credentials(), callback
      when Dropbox.Client.SIGNED_OFF
        @forgetCredentials callback
      when Dropbox.Client.ERROR
        @forgetCredentials callback
      else
        callback()

  # Shows the authorization URL in a pop-up, waits for it to send a message.
  doAuthorize: (authUrl, token, tokenSecret, callback) ->
    @listenForMessage token, callback
    @openWindow authUrl

  # Creates a popup window.
  #
  # @param {String} url the URL that will be loaded in the popup window
  # @return {?DOMRef} reference to the opened window, or null if the call
  #   failed
  openWindow: (url) ->
    chrome.tabs.create url: url, active: true, pinned: false

  # URL of the redirect receiver page, which posts a message to the extension.
  url: ->
    @receiverUrl

  # Listens for a postMessage from a previously opened tab.
  #
  # @param {String} token the token string that must be received from the tab
  # @param {function()} called when the received message matches the token
  listenForMessage: (token, callback) ->
    listener = (message, sender) =>
      # Reject messages not coming from the OAuth receiver window.
      unless sender.tab and sender.tab.url.substring(0, @receiverUrl.length) is
          @receiverUrl
        return
      match = @tokenRe.exec message.dropbox_oauth_receiver_href or ''
      if match and decodeURIComponent(match[2]) is token
        # window.close() doesn't work in tabs, so we close the receiver tab.
        chrome.tabs.remove sender.tab.id if sender.tab
        chrome.extension.onMessage.removeListener listener
        callback()
    chrome.extension.onMessage.addListener listener

  # Stores a Dropbox.Client's credentials to local storage.
  #
  # @private
  # onAuthStateChange calls this method during the authentication flow.
  #
  # @param {Object} credentials the result of a Drobpox.Client#credentials call
  # @param {function()} callback called when the storing operation is complete
  # @return {Dropbox.Drivers.BrowserBase} this, for easy call chaining
  storeCredentials: (credentials, callback) ->
    chrome.storage.local.set dropbox_js_credentials: credentials, callback
    @

  # Retrieves a token and secret from localStorage.
  #
  # @private
  # onAuthStateChange calls this method during the authentication flow.
  #
  # @param {function(?Object)} callback supplied with the credentials object
  #   stored by a previous call to
  #   Dropbox.Drivers.BrowserBase#storeCredentials; null if no credentials were
  #   stored, or if the previously stored credentials were deleted
  # @return {Dropbox.Drivers.BrowserBase} this, for easy call chaining
  loadCredentials: (callback) ->
    chrome.storage.local.get 'dropbox_js_credentials', (items) ->
      callback items.dropbox_js_credentials or null
    @
