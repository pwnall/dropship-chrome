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
    @startedAt = options.startedAt or Date.now()
    @uid = options.id or DropshipFile.randomUid()
    @size = options.size
    @size = null unless @size or @size is 0
    @errorText = options.errorText or null
    @_state = options.state or DropshipFile.NEW

    @_json = null
    @_basename = null

    @downloadedBytes = 0
    @uploadedBytes = 0
    @blob = null

  # @property {String} identifying string, unique to an extension instance
  uid: null

  # @property {String} URL where the file is downloaded from
  url: null

  # @property {String} value of the Referer header when downloading the file
  referrer: null

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
        url: @url, referrer: @referrer, startedAt: @startedAt, uid: @uid,
        size: @size, state: @_state, errorText: @errorText

  # @return {String} the file's name without the path, query string and
  #   URL fragment
  basename: ->
    return @_basename if @_basename

    basename = @url.substring @url.lastIndexOf('/') + 1
    basename = basename.split('?', 2)[0].split('#', 2)[0]
    @_basename = basename

  # Called while the file is downloading.
  #
  # @param {Number} downloadedBytes should be smaller or equal to totalBytes,
  #   if totalBytes is not null
  # @param {?Number} totalBytes the file's size, if known; null otherwise
  # @return {DropshipFile} this
  setDownloadProgress: (downloadedBytes, totalBytes) ->
    @_state = DropshipFile.DOWNLOADING
    @downloadedBytes = downloadedBytes
    @size = totalBytes if totalBytes
    @

  # Called while the file is uploading.
  #
  # @param {Number} uploadedBytes should be smaller or equal to totalBytes,
  #   if totalBytes is not null
  # @param {?Number} totalBytes the upload size, if known; null otherwise
  # @return {DropshipFile} this
  setUploadProgress: (uploadedBytes, totalBytes) ->
    @_state = DropshipFile.UPLOADING
    if totalBytes
      uploadOverhead = totalBytes - size
      @uploadedBytes = uploadedBytes - uploadOverhead
      @uploadedBytes = 0 if @uploadedBytes < 0
    else
      @uploadedBytes = uploadedBytes
    @

  # Called while the file is being saved to the database.
  #
  # @param {Number} savedBytes the number of bytes that have been already
  #   written to the database
  # @return {DropshipFile} this
  setSaveProgress: (writtenBytes) ->
    @_state = DropshipFile.SAVING
    @

  # Called when the Blob representing the file's content is available.
  #
  # @param {Blob} blob a Blob that has the file's contents
  # @return {DropshipFile} this
  setContents: (blob) ->
    @_state = DropshipFile.DOWNLOADED
    @downloadedBytes = blob.size
    @size = blob.size
    @blob = blob
    @

  # Called when a file's download ends due to an error.
  #
  # @param {Dropbox.ApiError} error the download error
  # @return {DropshipFile} this
  setDownloadError: (error) ->
    @_state = DropshipFile.ERROR
    @errorText = "Download error: #{error}"
    @

  # Called when a file's upload to Dropbox ends due to an error.
  #
  # @param {Dropbox.ApiError} error the Dropbox API server error
  # @return {DropshipFile} this
  setUploadError: (error) ->
    @_state = DropshipFile.ERROR
    @errorText = "Dropbox error: #{error}"
    @

  # Called when a file's upload to Dropbox completes.
  #
  # @param {Dropbox.Stat} stat the file's metadata in Dropbox
  # @return {DropshipFile} this
  setDropboxStat: (stat) ->
    @_state = DropshipFile.UPLOADED
    @blob = null
    @

  # @return {String} a randomly generated unique ID
  @randomUid: ->
    Date.now().toString(36) + Math.random().toString(36).substring(1)

  # state() value before the file has started downloading
  @NEW: 1

  # state() value when the file is being downloaded from its origin
  @DOWNLOADING: 2

  # state() value when the file was downloaded but hasn't started being
  #   uploaded to Dropbox
  @DOWNLOADED: 3

  # state() value when the file is being written to IndexedDB
  @SAVING: 4

  # state() value when the file is being uploaded to Dropbox
  @UPLOADING: 5

  # state() value when the file was uploaded to Dropbox
  @UPLOADED: 6

  # state() value when the file transfer failed due to an error
  @ERROR: 7

  # state() value when the file transfer was canceled
  @CANCELED: 8

window.DropshipFile = DropshipFile
