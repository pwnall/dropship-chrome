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

  # Fills in default values for missing settings.
  #
  # @private
  # Used internally by items(). Call items() instead of using this directly.
  #
  # @params {Object<String, Object>} an object passed to an
  #   OptionsModel#items() callback
  # @return
  addDefaults: (items) ->
    unless 'downloadSiteFolders' of items
      items.downloadSiteFolders = false
    unless 'downloadDateFolders' of items
      items.downloadDateFolders = false
    items

  # Number of milliseconds during which settings are cached.
  cacheDurationMs: 10 * 60

window.Options = Options
