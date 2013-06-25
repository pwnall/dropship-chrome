# Model class that tracks all the in-progress and completed downloads.
#
# This class is responsible for persisting the files' contents and metadata to
# IndexedDB.
class DropshipList
  constructor: ->
    @_files = null
    @_db = null
    @_dbLoadCallbacks = null
    @_fileGetCallbacks = null
    @_iops = {}
    @onDbError = new Dropbox.Util.EventSource
    @onStateChange = new Dropbox.Util.EventSource

  # @property {Dropbox.Util.EventSource<String>} fires non-cancelable events
  #   when a database error occurs; listeners should update the UI to reflect
  #   the error
  onDbError: null

  # @property {Dropbox.Util.EventSource<DropshipFile>} non-cancelable event
  #   fired when IndexedDB file I/O makes progress, completes, or stops due to
  #   an error; this event does not fire when the file I/O is canceled
  onStateChange: null

  # Adds a file to the list of files to be downloaded / uploaded.
  #
  # @param {DropshipFile} file the file to be added
  # @param {function(Boolean)} callback called when the file's metadata is
  #   persisted; the callback argument is true if an error occurred
  # @return {DropshipList} this
  addFile: (file, callback) ->
    @db (db) =>
      @getFiles (files) =>
        transaction = db.transaction 'metadata', 'readwrite'
        metadataStore = transaction.objectStore 'metadata'
        request = metadataStore.put file.json()
        transaction.oncomplete = =>
          files[file.uid] = file
          callback false
        transaction.onerror = (event) =>
          @handleDbError event
          callback true
    @

  # Updates the persisted metadata for a file to reflect changes.
  #
  # @param {DropshipFile} file the file whose state changed
  # @param {function(Boolean)} callback called when the file's metadata is
  #   persisted; the callback argument is true if an error occurred
  # @return {DropshipList} this
  updateFileState: (file, callback) ->
    @db (db) =>
      @getFiles (files) =>
        transaction = db.transaction 'metadata', 'readwrite'
        metadataStore = transaction.objectStore 'metadata'
        request = metadataStore.put file.json()
        transaction.oncomplete = =>
          files[file.uid] = file
          callback false
        transaction.onerror = (event) =>
          @handleDbError event
          callback true
    @

  # Removes the metadata for a file.
  #
  # @param {DropshipFile} file the file to be removed
  # @param {function(Boolean)} callback called when the file's data is
  #   removed; the callback argument is true if an error occurred
  # @return {DropshipList} this
  removeFileState: (file, callback) ->
    @removeFileStates [file], callback

  # Removes the metadata for a set of files.
  #
  # @param {Array<DropshipFile>} files the files to be removed
  # @param {function(Boolean)} callback called when the file's data is
  #   removed; the callback argument is true if an error occurred
  # @return {DropshipList} this
  removeFileStates: (files, callback) ->
    @db (db) =>
      @getFiles (_files) =>
        transaction = db.transaction 'metadata', 'readwrite'
        metadataStore = transaction.objectStore 'metadata'
        for file in files
          metadataStore.delete file.uid
        transaction.oncomplete = =>
          for file in files
            delete _files[file.uid]
          callback null
        transaction.onerror = (event) =>
          @handleDbError event
          callback event.target.error
    @

  # The mapping between file IDs and completed / in-progress file operations.
  #
  # @param {function(Object<String, DropshipFile>)} callback called with a
  #   consistent snapshot of the in-progress and completed download files
  # @return {DropshipList} this
  getFiles: (callback) ->
    if @_files
      callback @_files
      return @

    if @_fileGetCallbacks isnt null
      @_fileGetCallbacks.push callback
      return @

    @_fileGetCallbacks = [callback]
    files = {}
    @loadFiles files, (error) =>
      @_files = files
      callbacks = @_fileGetCallbacks
      @_fileGetCallbacks = null
      callback files for callback in callbacks

  # Loads the metadata for all the downloaded / uploaded files in memory.
  #
  # @private Called by getFiles.
  # @param {Object<String, DropshipFile>} results receives the file metadata,
  #   keyed by file IDs
  # @param {function(Boolean)} callback called when the metadata finished
  #   loading; the callback argument is true if something went wrong and the
  #   results array might contain metadata for all the files
  loadFiles: (results, callback) ->
    @db (db) =>
      transaction = db.transaction 'metadata', 'readonly'
      metadataStore = transaction.objectStore 'metadata'
      cursor = metadataStore.openCursor null, 'next'
      cursor.onsuccess = (event) =>
        cursor = event.target.result
        if cursor and cursor.key
          request = metadataStore.get cursor.key
          request.onsuccess = (event) =>
            json = event.target.result
            file = new DropshipFile json
            results[file.uid] = file
            cursor.continue()
          request.onerror = (event) =>
            @handleDbError event
            callback true
        else
          callback false
      cursor.onerror = (event) =>
        @handleDbError event
        callback true

  # Stores a file's contents in the database.
  #
  # @param {DropshipFile} file the file whose contents changed
  # @param {Blob} blob the file's contents
  # @param {function(?Error)} callback called when the file's contents is
  #   persisted; the callback argument is true if an error occurred
  # @return {DropshipList} this
  setFileContents: (file, blob, callback) ->
    file.setSaveProgress 0

    fileOffset = 0
    blockId = 0
    blockLoop = =>
      # Special case: we store empty files as 1 empty blob.
      # This lets us distinguish between a non-existing blob and an empty one.
      done = blockId isnt 0 and fileOffset >= file.size
      if done
        file.setSaveSuccess()
        @onStateChange.dispatch file
        return callback(null)

      if fileOffset + @blockSize >= blob.size
        currentBlockSize = blob.size - fileOffset
      else
        currentBlockSize = @blockSize

      blockBlob = blob.slice fileOffset, fileOffset + currentBlockSize
      @setFileBlock file, blockId, blockBlob, (error) =>
        if error
          file.setSaveError error
          @onStateChange.dispatch file
          return callback(error)
        blockId += 1
        fileOffset += currentBlockSize
        file.setSaveProgress fileOffset
        @onStateChange.dispatch file
        blockLoop()
    blockLoop()
    @

  # Stores a block of the file's contents in the database.
  #
  # @param {DropshipFile} file the file whose contents is being stored
  # @param {Number} blockId 0-based block sequence number
  # @param {Blob} blockBlob the contents of the file blob; this is not a Blob
  #   for the entire file
  # @param {function(?Error)} callback called when the file's contents is
  #   persisted; the callback argument is non-null if an error occurred
  # @return {DropshipList} this
  setFileBlock: (file, blockId, blockBlob, callback) ->
    @db (db) =>
      blobKey = @fileBlockKey file, blockId
      transaction = db.transaction 'blobs', 'readwrite'
      blobStore = transaction.objectStore 'blobs'
      try
        request = blobStore.put blockBlob, blobKey
        transaction.oncomplete = =>
          callback null
        transaction.onerror = (event) =>
          callback event.target.error
      catch e
        # Workaround for http://crbug.com/108012
        reader = new FileReader
        reader.onloadend = =>
          return unless reader.readyState == FileReader.DONE
          string = reader.result
          transaction = db.transaction 'blobs', 'readwrite'
          blobStore = transaction.objectStore 'blobs'
          blobStore.put string, blobKey
          transaction.oncomplete = =>
            callback null
          transaction.onerror = (event) =>
            callback event.target.error
        reader.onerror = (event) =>
          callback event.target.error
        reader.readAsBinaryString blockBlob

  # Cancels any pending IndexedDB operation involing a file.
  cancelFileContents: (file, callback) ->
    # TODO(pwnall): implement
    callback()
    @

  # The IndexedDB key for a file's block.
  #
  # @param {DropshipFile} file the file that the block belongs to
  # @param {Number} blockId 0-based block sequence number
  # @return {String} the key associated with the file block in the IndexedDB
  #   "blobs" table
  fileBlockKey: (file, blockId) ->
    # Padding
    stringId = blockId.toString 36
    while stringId.length < 8
      stringId = "0" + stringId

    # - comes right before all valid fileUid symbols in ASCII.
    "#{file.uid}-#{stringId}"

  # An upper bound for the IndexedDB keys for a file's blocks.
  fileMaxBlockKey: (file) ->
    # | comes after all blockId symbols in ASCII.
    "#{file.uid}-|"

  # Retrieves a file's contents from the database.
  #
  # @param {DropshipFile} file the file whose contents will be retrieved
  # @param {function(?Error, ?Blob)} callback called when the file's contents
  #   is available; the argument will be null if the file's contents was not
  #   found in the database
  # @return {DropshipList} this
  getFileContents: (file, callback) ->
    blockBlobs = []
    fileOffset = 0
    blockId = 0
    blockLoop = =>
      # Special case: we store empty files as 1 empty blob.
      # This lets us distinguish between a non-existing blob and an empty one.
      done = blockId isnt 0 and fileOffset >= file.size
      if done
        # NOTE: not reporting save success, the fetcher is responsible for
        #       setting things up
        @onStateChange.dispatch file
        return callback(null, new Blob(blockBlobs, type: blockBlobs[0].type))

      @getFileBlock file, blockId, (error, blockBlob) =>
        if error
          # Read error.
          file.setSaveError error
          @onStateChange.dispatch file
          return callback(error)
        if blockBlob is null
          # Missing block, so report file-not-found.
          return callback(null, null)
        blockBlobs.push blockBlob
        blockId += 1
        fileOffset += blockBlob.size
        file.setSaveProgress fileOffset
        @onStateChange.dispatch file
        blockLoop()
    blockLoop()
    @

  # Retrieves a block of the file's contents from the database.
  #
  # @param {DropshipFile} file the file whose contents will be retrieved
  # @param {Number} blockId 0-based block sequence number
  # @param {function(?Error, ?Blob)} callback called when the block's contents
  #   is available; if the block is not found in the database, both the error
  #   and the blob arguments will be null
  # @return {DropshipList} this
  getFileBlock: (file, blockId, callback) ->
    @db (db) =>
      blobKey = @fileBlockKey file, blockId
      transaction = db.transaction 'blobs', 'readonly'
      blobStore = transaction.objectStore 'blobs'
      request = blobStore.get blobKey
      request.onsuccess = (event) =>
        blockBlob = event.target.result
        unless blockBlob?
          # Incomplete save.
          return callback(null, null)

        # Workaround for http://crbug.com/108012
        if typeof blockBlob is 'string'
          string = blockBlob
          view = new Uint8Array string.length
          for i in [0...string.length]
            view[i] = string.charCodeAt(i) & 0xFF
          blockBlob = new Blob [view], type: 'application/octet-stream'
        callback null, blockBlob
      request.onerror = (event) =>
        callback event.target.error

  # Removes a file's contents from the database.
  #
  # @param {DropshipFile} file the file whose contents will be removed
  # @param {function(Boolean)} callback called when the file's contents is
  #   removed from the database; the callback argument is true if an error
  #   occurred
  # @return {DropshipList} this
  removeFileContents: (file, callback) ->
    @db (db) =>
      transaction = db.transaction 'blobs', 'readwrite'
      blobStore = transaction.objectStore 'blobs'
      keyRange = IDBKeyRange.bound @fileBlockKey(file, 0),
                                   @fileMaxBlockKey(file)
      cursor = blobStore.openCursor keyRange, 'next'
      cursor.onsuccess = (event) =>
        cursor = event.target.result
        if cursor and cursor.key
          request = cursor.delete()
          request.onsuccess = (event) =>
            cursor.continue()
          request.onerror = (event) =>
            callback event.target.error
        else
          callback null
      cursor.onerror = (event) =>
        callback event.target.error

  # Removes the contents of files whose metadata is missing.
  #
  # File contents and metadata is managed separately. If an attempt to remove a
  # file's contents Blob fails, but the metadata remove succeeds, the Blob
  # becomes stranded, as it will never be accessed again. Vacuuming removes
  # stranded Blobs so the database size doesn't keep growing.
  #
  # @param {function(Boolean)} callback called when the vacuuming completes;
  #   the callback argument is true if an error occurred
  # @return {DropshopList} this
  vacuumFileContents: (callback) ->
    # TODO(pwnall): implement early exit using count() on blobs and metadata
    # TODO(pwnall): implement blob enumeration and kill dangling blobs
    callback()
    @

  # @param {function(Boolean)} callback called when the vacuuming completes;
  #   the callback argument is true if an error occurred
  # @return {DropshopList} this
  removeDb: (callback) ->
    @db (db) =>
      @getFiles (files) =>
        db.close() if db
        request = indexedDB.deleteDatabase @dbName
        request.oncomplete = =>
          @_db = null
          @_files = null
          callback false
        request.onerror = (event) =>
          @onDbError.dispatch event.target.error
          @_db = null
          @_files = null
          callback true

  # The IndexedDB database caching this extension's files.
  #
  # @param {function(IDBDatabase)} callback called when the database is ready
  #   for use
  # @return {DropshipList} this
  db: (callback) ->
    if @_db
      callback @_db
      return @

    # Queue up the callbacks while the database is being opened.
    if @_dbLoadCallbacks isnt null
      @_dbLoadCallbacks.push callback
      return @
    @_dbLoadCallbacks = [callback]

    request = indexedDB.open @dbName, @dbVersion
    request.onsuccess = (event) =>
      @openedDb event.target.result
    request.onupgradeneeded = (event) =>
      db = event.target.result
      @migrateDb db, event.target.transaction, (error) =>
        if error
          @openedDb null
        else
          @openedDb db
    request.onerror = (event) =>
      @handleDbError event
      @openedDb null
    @

  # Called when the IndexedDB is available for use.
  #
  # @private Called by handlers to IndexedDB events.
  # @param {IDBDatabase} db
  # @return {DropshipList} this
  openedDb: (db) ->
    return unless @_dbLoadCallbacks

    @_db = db
    callbacks = @_dbLoadCallbacks
    @_dbLoadCallbacks = null
    callback db for callback in callbacks
    @

  # Sets up the IndexedDB schema.
  #
  # @private Called by the IndexedDB API.
  #
  # @param {IDBDatabase} db the database connection
  # @param {IDBTransaction} transaction the 'versionchange' transaction
  # @param {function()} callback called when the database is migrated to the
  #   latest schema version
  # @return {DropshipList} this
  migrateDb: (db, transaction, callback) ->
    if db.objectStoreNames.contains 'blobs'
      db.deleteObjectStore 'blobs'
    db.createObjectStore 'blobs'
    if db.objectStoreNames.contains 'metadata'
      db.deleteObjectStore 'metadata'
    db.createObjectStore 'metadata', keyPath: 'uid'
    transaction.oncomplete = =>
      callback false
    transaction.onerror = (event) =>
      @handleDbError event
      callback true
    @

  # Reports IndexedDB errors.
  #
  # The best name for this method would have been 'onDbError', but that's taken
  # by a public API element.
  #
  # @param {#target, #target.error} event the IndexedDB error event
  handleDbError: (event) ->
    error = event.target.error
    # TODO(pwnall): better error string
    errorString = "IndexedDB error: #{error}"
    @onDbError.dispatch errorString

  # IndexedDB database name. This should not change.
  dbName: 'dropship_files'

  # IndexedDB schema version.
  dbVersion: 1

  # The size of an atomic IndexedDB read / write and of a file upload chunk.
  blockSize: 1 * 1024 * 1024

window.DropshipList = DropshipList
