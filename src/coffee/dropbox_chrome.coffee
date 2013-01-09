# Common functionality for Chrome apps / extensions using dropbox.js.
class Dropbox.Chrome
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
  # @param {function(Dropbox.Client)} callback called with a properly set up
  #   Dropbox.Client instance
  # @return {Dropbox.Chrome} this
  client: (callback) ->
    if @_client
      callback @_client
      return @

    authDriver = new Dropbox.Drivers.Chrome(
        receiverPath: 'html/chrome_oauth_receiver.html')
    authDriver.loadCredentials (credentials) =>
      unless credentials and credentials.token and credentials.tokenSecret
        # Missing or corrupted credentials.
        credentials = @clientOptions
      @_client = new Dropbox.Client credentials
      @_client.authDriver authDriver
      @onClient.dispatch @_client
      callback @_client
    @

  # Returns a (potentially cached) version of the Dropbox user's information.
  #
  # @param {function(Dropbox.UserInfo)} callback called when the
  #   Dropbox.UserInfo becomes available
  # @return {Dropbox.Chrome} this
  userInfo: (callback) ->
    if @_userInfo
      callback @_userInfo
      return null

    chrome.storage.local.get 'dropbox_js_userinfo', (items) =>
      if items && items.dropbox_js_userinfo
        try
          @_userInfo = Dropbox.UserInfo.parse items.dropbox_js_userinfo
          return callback @_userInfo
        catch Error
          # There was a parsing error. Let the control flow fall.

      @client (client) =>
        client.getUserInfo (error, userInfo) =>
          return if error
          @_userInfo = userInfo
          chrome.storage.local.set dropbox_js_userinfo: userInfo.json(), =>
            callback @_userInfo
    null

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
