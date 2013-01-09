# Model class that tracks all the in-progress and completed downloads.
#
# This class is responsible for persisting the files' contents and metadata to
# IndexedDB.
class DropshipList
  constructor: ->
    @_files = {}
    @_db = null
    @onDbError = new Dropbox.EventSource

  # @property {Dropbox.EventSource<String>} fires non-cancelable events when a
  #   database error occurs; listeners should update the UI to reflect the
  #   error
  onDbError: null

  # Adds a file to the list of files to be downloaded / uploaded.
  #
  # @param {DropshipFile} file the file to be added
  # @param {function(Boolean)} callback called when the file's metadata is
  #   persisted; the callback argument is true if an error occurred
  # @return {DropshipList} this
  addFile: (file, callback) ->
    @db (db) =>
      transaction = db.transaction 'metadata', 'readwrite'
      metadataStore = transaction.objectStore 'metadata'
      request = metadataStore.put file.json()
      transaction.oncomplete = =>
        @_files[file.uid] = file
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
      transaction = db.transaction 'metadata', 'readwrite'
      metadataStore = transaction.objectStore 'metadata'
      request = metadataStore.put file.json()
      transaction.oncomplete = =>
        @_files[file.uid] = file
        callback false
      transaction.onerror = (event) =>
        @handleDbError event
        callback true
    @

  # Stores a file's contents in the database.
  #
  # @param {DropshipFile} file the file whose contents changed
  # @param {Blob} blob the file's contents
  # @param {function(Boolean)} callback called when the file's contents is
  #   persisted; the callback argument is true if an error occurred
  # @return {DropshipList} this
  setFileContents: (file, blob, callback) ->
    file.setSaveProgress 0
    @db (db) =>
      transaction = db.transaction 'blobs', 'readwrite'
      blobStore = transaction.objectStore 'blobs'
      try
        request = blobStore.put file.blob, file.uid
        transaction.oncomplete = =>
          file.setSaveProgress file.size
          callback false
        transaction.onerror = (event) =>
          @handleDbError event
          callback true
      catch e
        # http://crbug.com/108012
        reader = new FileReader
        reader.onloadend = =>
          return unless reader.readyState == FileReader.DONE
          string = reader.result
          transaction = db.transaction 'blobs', 'readwrite'
          blobStore = transaction.objectStore 'blobs'
          blobStore.put string, file.uid
          transaction.oncomplete = =>
            file.setSaveProgress file.size
            callback false
          transaction.onerror = (event) =>
            @handleDbError event
            callback true
        reader.readAsBinaryString blob
    @

  # Retrieves a file's contents from the database.
  #
  # @param {DropshipFile} file the file whose contents will be retrieved
  # @param {function(Blob)} callback called when the file's contents is
  #   available
  # @return {DropshipList} this
  getFileContents: (file, callback) ->
    @db (db) =>
      transaction = db.transaction 'blobs', 'readonly'
      blobStore = transaction.objectStore 'blobs'
      request = blobStore.get file.uid
      request.onsuccess = (event) =>
        blob = event.target.result
        callback blob, file
      request.onerror = (event) =>
        callback null, file

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
      request = blobStore.delete file.uid
      transaction.oncomplete = =>
        callback false
      transaction.onerror = (event) =>
        @handleDbError event
        callback true

  # Produces a consistent view of the in-progress and completed downloads.
  #
  # @param {function(Array<DropshipFile>)} callback called with a
  #   consistent snapshot of the in-progress and completed download files
  # @return {DropshipList} this
  getFiles: (callback) ->
    fileArray = []
    for _, file of @_files
      fileArray.push file
    callback fileArray
    @

  # The IndexedDB database caching this extension's files.
  #
  # @private Called by the constructor.
  # @param {function(IDBDatabase)} callback
  # @return {DropshipList} this
  db: (callback) ->
    if @_db
      callback @_db
      @

    indexedDB = window.indexedDB or window.webkitIndexedDB
    request = indexedDB.open @dbName, @dbVersion
    request.onsuccess = (event) =>
      @_db = event.target.result
      callback @_db
    request.onupgradeneeded = (event) =>
      @_db = event.target.result
      @migrateDb @_db, event.target.transaction, (error) =>
        if error
          callback null
        else
          callback @_db
    request.onerror = (event) =>
      @handleDbError event
      callback null
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
    errorString = "IndexedDB error"
    @onDbError.dispatch errorString

  # IndexedDB database name. This should not change.
  dbName: 'dropship_files'

  # IndexedDB schema version.
  dbVersion: 1

window.DropshipList = DropshipList
