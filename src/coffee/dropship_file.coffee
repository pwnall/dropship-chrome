# Model class that tracks one in-progress or downloaded file.
class DropshipFile
  # @param {Object} options one or more of the attributes below
  # @option options {String} url URL where the file is downloaded from
  # @option options {String} referrer value of the Referer header of the
  #   downloading HTTP request
  # @option options {Number} startedAt the time when the user asked to have the
  #   file downloaded
  # @option options {String} uid identifying string, unique to an extension
  #   instance
  # @option options {Number} size file's size, in bytes; this is only known
  #   after the file's download starts
  # @option options {Number} state file's progress in the download / upload
  #   process
  # @option options {String} errorText user-friendly message describing the
  #   download/upload error
  constructor: (options) ->
    @url = options.url
    @referrer = options.referrer or null
    @dropboxPath = options.dropboxPath or null
    @startedAt = options.startedAt or Date.now()
    @uid = options.uid or DropshipFile.randomUid()
    @size = options.size
    @size = null unless @size or @size is 0
    @errorText = options.errorText or null
    @_state = options.state or DropshipFile.NEW

    @_json = null
    @_basename = null

    @_downloadedBytes = 0
    @_savedBytes = 0
    @_uploadedBytes = 0
    @blob = null

  # @property {String} identifying string, unique to an extension instance
  uid: null

  # @property {String} URL where the file is downloaded from
  url: null

  # @property {String} value of the Referer header when downloading the file
  referrer: null

  # @property {String} the path of this file, relative to the application's
  #   Dropbox folder
  dropboxPath: null

  # @property {Number} the time when the user asked to have the file
  #   downloaded; this should only be used for relative comparison among
  #   DropshipFile instances on the same extension instance
  startedAt: null

  # @property {Number} the file's size, in bytes
  size: null

  # @property {String} errorText
  errorText: null

  # @return {Number} one of the DropshipFile constants indicating this file's
  #   progress in the download / upload process
  state: -> @_state

  # @return {Object} JSON object that can be passed to the DropshipFile
  #   constructor to build a clone for this file; intended to preserve the
  #   file's contents
  json: ->
    @_json ||=
        url: @url, referrer: @referrer, dropboxPath: @dropboxPath,
        startedAt: @startedAt, uid: @uid, size: @size, state: @_state,
        errorText: @errorText

  # @return {String} the file's name without the path, query string and
  #   URL fragment
  basename: ->
    return @_basename if @_basename

    if @dropboxPath
      basename = @dropboxPath
      basename = basename.substring basename.lastIndexOf('/') + 1
      @_basename = basename
    else
      @_basename = @uploadBasename()

  # @return {String} the name used when uploading this file to Dropbox
  #   URL fragment
  uploadBasename: ->
    basename = @url.split('#', 2)[0].split('?', 2)[0]
    while basename.substring(basename.length - 1) == '/'
      basename = basename.substring 0, basename.length - 1
    basename.substring basename.lastIndexOf('/') + 1

  # Called while the file is downloading.
  #
  # @param {Number} downloadedBytes should be smaller or equal to totalBytes,
  #   if totalBytes is not null
  # @param {?Number} totalBytes the file's size, if known; null otherwise
  # @return {DropshipFile} this
  setDownloadProgress: (downloadedBytes, totalBytes) ->
    @_state = DropshipFile.DOWNLOADING
    @_downloadedBytes = downloadedBytes
    @_savedBytes = 0
    @_uploadedBytes = 0
    @size = totalBytes if totalBytes
    @_json = null
    @

  # @return {Number} the number of bytes that have been already downloaded
  downloadedBytes: ->
    if @_state is DropshipFile.DOWNLOADING
      @_downloadedBytes or 0
    else if @_state > DropshipFile.DOWNLOADING
      @size
    else
      0

  # @return {Number} the number of bytes that have been alredy written to
  #   IndexedDB
  savedBytes: ->
    if @_state is DropshipFile.SAVING
      @_savedBytes or 0
    else if @_state > DropshipFile.SAVING
      @size
    else
      0

  # @return {Number} the number of bytes that have been alredy uploaded
  uploadedBytes: ->
    if @_state is DropshipFile.UPLOADING
      @_uploadedBytes or 0
    else if @_state > DropshipFile.UPLOADING
      @size
    else
      0

  # Called while the file is uploading.
  #
  # @param {Number} uploadedBytes should be smaller or equal to totalBytes,
  #   if totalBytes is not null
  # @param {?Number} totalBytes the upload size, if known; null otherwise
  # @return {DropshipFile} this
  setUploadProgress: (uploadedBytes, totalBytes) ->
    @_state = DropshipFile.UPLOADING
    if totalBytes
      uploadOverhead = totalBytes - @size
      @_uploadedBytes = uploadedBytes - uploadOverhead
      @_uploadedBytes = 0 if @_uploadedBytes < 0
    else
      @_uploadedBytes = uploadedBytes
    @_json = null
    @

  # Called while the file is being saved to IndexedDB.
  #
  # @param {Number} savedBytes the number of bytes that have been already
  #   written to IndexedDB
  # @return {DropshipFile} this
  setSaveProgress: (savedBytes) ->
    @_state = DropshipFile.SAVING
    @_savedBytes = savedBytes
    @

  # Called when the file is fully saved to IndexedDB.
  #
  # @return {DropshipFile} this
  setSaveSuccess: ->
    @_state = DropshipFile.SAVED
    @

  # Called when the Blob representing the file's content is available.
  #
  # @param {Blob} blob a Blob that has the file's contents
  # @return {DropshipFile} this
  setContents: (blob) ->
    @_state = DropshipFile.DOWNLOADED
    @_downloadedBytes = null
    @size = blob.size
    @blob = blob
    @_json = null
    @

  # Called when a file's download ends due to an error.
  #
  # @param {Dropbox.ApiError} error the download error
  # @return {DropshipFile} this
  setDownloadError: (error) ->
    @_state = DropshipFile.ERROR
    @errorText = "Download error: #{error}"
    @_json = null
    @

  # Called when a file's save to IndexedDB ends due to an error.
  #
  # @param {Error} error the IndexedDB error
  # @return {DropshipFile} this
  setSaveError: (error) ->
    @_state = DropshipFile.ERROR
    @errorText = "Disk error: #{error}"
    @_json = null
    @

  # Called when a file's upload to Dropbox ends due to an error.
  #
  # @param {Dropbox.ApiError} error the Dropbox API server error
  # @return {DropshipFile} this
  setUploadError: (error) ->
    @_state = DropshipFile.ERROR
    @errorText = "Dropbox error: #{error}"
    @_json = null
    @

  # Called when a file's upload to Dropbox completes.
  #
  # @param {Dropbox.Stat} stat the file's metadata in Dropbox
  # @return {DropshipFile} this
  setDropboxStat: (stat) ->
    @dropboxPath = stat.path
    @_basename = null  # Invalidated so it's recomputed using dropboxPath.
    @_state = DropshipFile.UPLOADED
    @_uploadedBytes = null
    @blob = null
    @_json = null
    @

  # Called when a file's download is canceled.
  setCanceled: ->
    @_state = DropshipFile.CANCELED
    @errorText = "Download canceled."
    @blob = null
    @_json = null
    @

  # @return {Boolean} true if this file download / upload can be canceled
  canBeCanceled: ->
    @_state < DropshipFile.UPLOADED

  # @return {Boolean} true if this file download / upload can be hidden
  canBeHidden: ->
    @_state >= DropshipFile.UPLOADED

  # @return {Boolean} true if this file download / upload can be retried
  canBeRetried: ->
    @_state >= DropshipFile.UPLOADED

  # @return {String} a randomly generated unique ID
  @randomUid: ->
    Date.now().toString(36) + '_' + Math.random().toString(36).substring(2)

  # state() value before the file has started downloading
  @NEW: 1

  # state() value when the file is being downloaded from its origin
  @DOWNLOADING: 2

  # state() value when the file was downloaded, but hasn't started being
  #   written to IndexedDB
  @DOWNLOADED: 3

  # state() value when the file is being written to IndexedDB
  @SAVING: 4

  # state() value when the file was written to IndexedDB, but hasn't started
  #   being uploaded to Dropbox
  @SAVED: 5

  # state() value when the file is being uploaded to Dropbox
  @UPLOADING: 5

  # state() value after the file was uploaded to Dropbox
  @UPLOADED: 6

  # state() value when the file transfer failed due to an error
  @ERROR: 7

  # state() value when the file transfer was canceled
  @CANCELED: 8

window.DropshipFile = DropshipFile
