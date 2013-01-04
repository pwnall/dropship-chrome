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


