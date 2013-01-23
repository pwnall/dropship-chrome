# Manages the extension settings, which are synced across Chrome instances.
class Options
  constructor: ->
    @_items = null
    @_itemsCallbacks = null
    @loadedAt = null

  # Reads the settings from Chrome's synchronied storage.
  #
  # @param {function(Object<String, Object>)} callback called when the settings
  #   are available
  # @return {OptionsModel} this
  items: (callback) ->
    if @_items
      if Date.now() - @loadedAt < @cacheDurationMs
        callback @_items
        return @
      else
        @_items = null

    if @_itemsCallbacks
      @_itemsCallbacks.push callback
      return @

    @_itemsCallbacks = [callback]
    chrome.storage.sync.get 'settings', (storage) =>
      items = storage.settings || {}
      @addDefaults items
      @_items = items
      @loadedAt = Date.now()
      callbacks = @_itemsCallbacks
      @_itemsCallbacks = null
      for callback in callbacks
        callback @_items
    @

  # Writes the settings to Chrome's synchronized storage.
  #
  # @param {Object<String, Object>} items the settings to be written; this
  #   should be the object passed to an OptionsModel#items() callback,
  #   optionally with some properties modified
  # @return {OptionsModel} this
  setItems: (items, callback) ->
    chrome.storage.sync.set settings: items, =>
      @_items = items
      @loadedAt = Date.now()
      callback() if callback
    @

  # Computes the location of a downloaded item for the example in options.
  #
  # @param {Object<String, Object>} items object passed to an
  #   OptionsModel#items() callback
  # @return {String} the download location, relative to the user's Dropbox
  sampleDownloadFolder: (items, callback) ->
    folder = '/Apps/Chrome Downloads'
    if items.downloadDateFolder
      folder += '/' + humanize.date('Y-m-d', new Date())
    if items.downloadSiteFolder
      folder += '/en.wikipedia.org'
    folder

  # Fills in default values for missing settings.
  #
  # @private
  # Used internally by items(). Call items() instead of using this directly.
  #
  # @params {Object<String, Object>} an object passed to an
  #   OptionsModel#items() callback
  # @return
  addDefaults: (items) ->
    unless 'downloadSiteFolder' of items
      items.downloadSiteFolder = false
    unless 'downloadDateFolder' of items
      items.downloadDateFolder = false
    items

  # Number of milliseconds during which settings are cached.
  cacheDurationMs: 10 * 60

window.Options = Options
