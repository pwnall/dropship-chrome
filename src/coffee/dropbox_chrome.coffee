# Common functionality for Chrome apps / extensions using dropbox.js.
class Dropbox.Chrome
  # @param {Object} options to be passed to the Dropbox API client; the object
  #     should have the property 'key'
  constructor: (@clientOptions) ->
    @_client = null
    @_clientCallbacks = null
    @_userInfo = null
    @_userInfoCallbacks = null
    @onClient = new Dropbox.Util.EventSource

  # @property {Dropbox.Util.EventSource<Dropbox.Client>} triggered when a new
  #   Dropbox.Client instance is created; can be used to attach listeners to
  #   the client
  onClient: null

  # Produces a properly set up Dropbox API client.
  #
  # @param {function(Dropbox.Client)} callback called with a properly set up
  #   Dropbox.Client instance
  # @return {Dropbox.Chrome} this
  client: (callback) ->
    if @_client
      callback @_client
      return @

    if @_clientCallbacks
      @_clientCallbacks.push callback
      return @
    @_clientCallbacks = [callback]

    client = new Dropbox.Client @clientOptions
    client.authDriver new Dropbox.AuthDriver.ChromeExtension(
        receiverPath: 'html/chrome_oauth_receiver.html')
    # Try loading cached credentials, if they are available.
    client.authenticate interactive: false, (error) =>
      # Drop the cached user info when the credentials become invalid.
      client.onAuthStepChange.addListener =>
        @_userInfo = null

      @onClient.dispatch client
      @_client = client
      callbacks = @_clientCallbacks
      @_clientCallbacks = null
      callback(@_client) for callback in callbacks
    @

  # Returns a (potentially cached) version of the Dropbox user's information.
  #
  # @param {function(Dropbox.AccountInfo)} callback called when the
  #   Dropbox.AccountInfo becomes available
  # @return {Dropbox.Chrome} this
  userInfo: (callback) ->
    if @_userInfo
      callback @_userInfo
      return @

    if @_userInfoCallbacks
      @_userInfoCallbacks.push callback
      return @
    @_userInfoCallbacks = [callback]

    dispatchUserInfo = =>
      callbacks = @_userInfoCallbacks
      @_userInfoCallbacks = null
      callback(@_userInfo) for callback in callbacks

    chrome.storage.local.get 'dropbox_js_userinfo', (items) =>
      if items and items.dropbox_js_userinfo
        try
          @_userInfo = Dropbox.AccountInfo.parse items.dropbox_js_userinfo
          return dispatchUserInfo()
        catch parseError
          @_userInfo = null
          # There was a parsing error. Let the control flow fall.

      @client (client) =>
        unless client.isAuthenticated()
          @_userInfo = {}
          return dispatchUserInfo()
        client.getUserInfo (error, userInfo) =>
          if error
            @_userInfo = {}
            return dispatchUserInfo()
          chrome.storage.local.set dropbox_js_userinfo: userInfo.json(), =>
            @_userInfo = userInfo
            dispatchUserInfo()
    @

  # Signs the user out of Dropbox and clears their cached information.
  #
  # @param {function()} callback called when the user's token is invalidated
  #   and the cached information is removed
  # @return {Dropbox.Chrome} this
  signOut: (callback) ->
    @client (client) =>
      unless client.isAuthenticated()
        return callback()

      client.signOut =>
        @_userInfo = null
        chrome.storage.local.remove 'dropbox_js_userinfo', =>
          callback()
