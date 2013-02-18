# Reports the browser's HTTP requests that match the auto-download criteria.
class WebRequestTracker
  # @param {Options} options the extension's settings manager
  constructor: (@options) ->
    @requestHeaders = {}
    @onFilterMatch = new Dropbox.EventSource

    @onErrorListener = null
    @onSendHeadersListener = (details) => @onWebRequestSendHeaders details
    @onHeadersReceivedListener = (details) =>
      @onWebRequestHeadersReceived details
    @onCompletedListener = (details) => @onWebRequestCompleted details
    @onErrorListener = (details) => @onWebRequestError details

    @extRegexps = []
    @mimeRegexps = []
    @onOptionsChange()

    @options.onChange.addListener => @onOptionsChange()

  # @property {Dropbox.EventSource<DropshipFile>} fires non-cancelable events
  #   when a browser request matches the user's filters
  onFilterMatch: null

  # Updates the WebRequest filters to match auto-download criteria changes.
  onOptionsChange: ->
    @options.items (items) =>
      if items.autoDownload
        @hookWebRequests items
        @extRegexps = for ext in items.autoDownloadExts
          new RegExp "\.#{@globToRegExp(ext)}$", 'i'
        @mimeRegexps = for ext in items.autoDownloadMimes
          new RegExp "^#{@globToRegExp(ext)}$", 'i'
      else
        @unhookWebRequests()

  # Sets up the listeners for WebRequest events.
  hookWebRequests: (items) ->
    filter =
        urls: ['<all_urls>'],
        types: ['main_frame', 'sub_frame', 'stylesheet', 'script', 'image',
                'object', 'xmlhttprequest', 'other']
    chrome.webRequest.onSendHeaders.addListener @onSendHeadersListener, filter,
        ["requestHeaders"]
    chrome.webRequest.onCompleted.addListener @onCompletedListener, filter,
        ["responseHeaders"]
    chrome.webRequest.onErrorOccurred.addListener @onErrorListener, filter
    @

  # Removes the previously set listeners for WebRequest events.
  unhookWebRequests: ->
    chrome.webRequest.onSendHeaders.removeListener @onSendHeadersListener
    chrome.webRequest.onCompleted.removeListener @onCompletedListener
    chrome.webRequest.onErrorOccurred.removeListener @onErrorListener

  # Called when the request headers of a HTTP request are available.
  onWebRequestSendHeaders: (details) ->
    # Filter request coming from extensions.
    # This is a nice and easy way to filter our own requests.
    return if details.tabId is -1

    # TODO(pwnall): eager URL-based filtering using details.url

    @requestHeaders[details.requestId] = details.requestHeaders

  # Called when the browser completes a HTTP request.
  onWebRequestCompleted: (details) ->
    return unless requestHeaders = @requestHeaders[details.requestId]
    delete @requestHeaders[details.requestId]

    return unless @filterWebRequest details, requestHeaders

    headers = {}
    for header in requestHeaders
      headers[header.name] = header.value
    file = new DropshipFile(
        httpMethod: details.method, url: details.url, headers: headers)
    @onFilterMatch.dispatch file

  # Checks a HTTP request against the auto-grab criteria.
  #
  # @param {Object} webRequest the "details" object passed to WebRequest events
  # @param {Array<String, String>} headers the requestHeaders property of the
  #   "details" object passed to WebRequest events
  # @return {Boolean} true if the request matches the user's filters and its
  #   response should be saved to Dropbox
  filterWebRequest: (request, headers) ->
    # Skip HTTP errors.
    if request.statusCode < 200 or request.statusCode >= 400
      return false

    # URL filtering.
    url = @webRequestUrl request
    for regexp in @extRegexps
      return true if regexp.test url

    # Content-Type filtering.
    contentType = @webRequestContentType request
    for regexp in @mimeRegexps
      return true if regexp.test contentType

    console.log 'false'
    false

  # Finds the Content-Type in a WebRequest "details" object.
  #
  # @param {Object} webRequest the "details" object passed to WebRequest events
  # @return {String} the value of the Content-Type header in the request's
  #   response;
  webRequestContentType: (webRequest) ->
    contentTypeRe = /^content-type$/i
    return null unless responseHeaders = webRequest.responseHeaders
    for header in responseHeaders
      if contentTypeRe.test header.name
        # Remove charset specifiers, e.g. "text/html; charset=utf-8".
        return header.value.split(';', 1)[0].trim()
    null

  # Finds the protocol, host, port and path in a WebRequest "details" object.
  #
  # @param {Object} webRequest the "details" object passed to WebRequest events
  # @return {String} the value of the request URL, minus query parameters and
  #   fragment
  webRequestUrl: (webRequest) ->
    return null unless url = webRequest.url
    url.split('#', 1)[0].split('?', 1)[0]

  # Called when something goes wrong with an HTTP request.
  onWebRequestError: (details) ->
    delete @requestHeaders[details.requestId]

  # Turns a pattern in the glob syntax into a regular expression.
  #
  # Essentially, substitutes ? with . and * with .* and escapes the other
  # regular expression operators.
  #
  # @param {String} glob pattern using the glob syntax
  # @return {String} regular expression that matches the glob, minus the
  #   heading ^ and trailing $
  globToRegExp: (glob) ->
    glob.replace(/\./g, '.').replace(/\*/g, '.*').
         replace(/[-\/\\^$+?()|[\]{}]/g, '\\$&')

window.WebRequestTracker = WebRequestTracker
