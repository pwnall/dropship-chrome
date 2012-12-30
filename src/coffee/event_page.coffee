_client = null

# A properly set up Dropbox API client.
#
# @param {function(Dropbox.Client)} callback called with the Dropbox.Client
#   instance
# @return {null} null
getClient = (callback) ->
  if _client
    callback _client
    return null

  authDriver = new Dropbox.Drivers.ChromeExtension(
      receiverPath: 'html/chrome_oauth_receiver.html')
  authDriver.loadCredentials (credentials) ->
    unless credentials && credentials.key
      # Missing or corrupted credentials.
      credentials =
          key: 'CAI0akf5IgA=|sy+zEdXhRdoi11JXtONSBP0mUVgcnNbU/8/HCaVE7w=='
    _client = new Dropbox.Client credentials
    _client.authDriver authDriver
    callback _client
  null

# Updates the badge tooltip and badge to reflect the current browser state.
updateBadge = ->
  getClient (client) ->
    credentials = client.credentials()
    if credentials.authState
      chrome.browserAction.setTitle title: 'Signing in...'
      chrome.browserAction.setBadgeText text: '...'
      chrome.browserAction.setBadgeBackgroundColor color: '#DFBF20'
    else if credentials.tokenSecret
      chrome.browserAction.setTitle title: 'Signed in'
      chrome.browserAction.setBadgeText text: ''
      client.getUserInfo (error, userInfo) ->
        # TODO(pwnall): log out in case of error
        chrome.browserAction.setTitle(
            title: "Signed in as #{userInfo.name} <#{userInfo.email}>")
        chrome.browserAction.setBadgeText text: ''
    else
      chrome.browserAction.setTitle title: 'Click to sign into Dropbox'
      chrome.browserAction.setBadgeText text: '?'
      chrome.browserAction.setBadgeBackgroundColor color: '#DF2020'

# Called by Chrome when the user clicks the browser action.
chrome.browserAction.onClicked.addListener ->
  getClient (client) ->
    credentials = client.credentials()
    if credentials.authState
      # Signing in.
    else if credentials.tokenSecret
      # Open a tab with the browser.
    else
      # Start the sign-in process.
      client.authenticate ->
        updateBadge()

chrome.runtime.onInstalled.addListener ->
  updateBadge()
  # TODO(pwnall): display a welcome page

chrome.runtime.onStartup.addListener ->
  updateBadge()

