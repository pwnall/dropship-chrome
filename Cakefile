async = require 'async'
{spawn, exec} = require 'child_process'
fs = require 'fs-extra'
glob = require 'glob'
log = console.log
path = require 'path'
remove = require 'remove'

# Node 0.6 compatibility hack.
unless fs.existsSync
  fs.existsSync = (filePath) -> path.existsSync filePath


task 'build', ->
  vendor ->
    build()

task 'release', ->
  vendor ->
    build ->
      release()

task 'vendor', ->
  vendor()

task 'clean', ->
  clean()

build = (callback) ->
  for dir in ['build', 'build/css', 'build/html', 'build/images', 'build/js',
              'build/vendor']
    fs.mkdirSync dir unless fs.existsSync dir

  commands = []
  commands.push 'cp src/manifest.json build/'
  commands.push 'cp -r src/html build/'
  # TODO(pwnall): consider optipng
  commands.push 'cp -r src/images build/'
  for inFile in glob.sync 'src/css/**/*.css'
    continue if path.basename(inFile).match /^_/
    outFile = inFile.replace /^src\//, 'build/'
    commands.push "node_modules/less/bin/lessc --strict-imports #{inFile} " +
                  "> #{outFile}"
  for inFile in glob.sync 'vendor/*.js'
    continue if inFile.match /\.min\.js$/
    outFile = 'build/' + inFile
    commands.push "cp #{inFile} #{outFile}"
  commands.push 'node_modules/coffee-script/bin/coffee --output build/js ' +
                '--compile src/coffee/*.coffee'
  async.forEachSeries commands, run, ->
    callback() if callback

release = (callback) ->
  for dir in ['release', 'release/css', 'release/html', 'release/images',
              'release/js', 'release/vendor']
    fs.mkdirSync dir unless fs.existsSync dir

  commands = []
  commands.push 'cp build/manifest.json release/'
  # TODO(pwnall): consider a html minifier
  commands.push 'cp -r build/html release/'
  commands.push 'cp -r build/images release/'
  for inFile in glob.sync 'build/js/*.js'
    outFile = inFile.replace /^build\//, 'release/'
    commands.push 'node_modules/uglify-js/bin/uglifyjs --compress --mangle ' +
                  "--output #{outFile} #{inFile}"
  for inFile in glob.sync 'vendor/*.min.js'
    outFile = 'release/' + inFile.replace /\.min\.js$/, '.js'
    commands.push "cp #{inFile} #{outFile}"

  async.forEachSeries commands, run, ->
    callback() if callback

clean = (callback) ->
  remove 'build', ignoreMissing: true, ->
    remove 'release', ignoreMissing: true,
      callback

vendor = (callback) ->
  fs.mkdirSync 'vendor' unless fs.existsSync 'vendor'
  downloads = [
    ['https://cdnjs.cloudflare.com/ajax/libs/dropbox.js/0.7.2/dropbox.min.js',
     'vendor/dropbox.min.js'],

    # Zepto.js is a small subset of jQuery.
    ['http://zeptojs.com/zepto.js', 'vendor/zepto.js'],
    ['http://zeptojs.com/zepto.min.js', 'vendor/zepto.min.js']
  ]

  async.forEachSeries downloads, download, ->
    # If a dropbox-js development tree happens to be checked out next to
    # the extension, copy the dropbox.js files from there.
    commands = []
    if fs.existsSync '../dropbox-js/lib/dropbox.js'
      commands.push 'cp ../dropbox-js/lib/dropbox.js vendor/'
    else
      # If there is no development dir, use the minified dropbox.js everywhere.
      unless fs.existsSync 'vendor/dropbox.js'
        commands.push 'cp vendor/dropbox.min.js vendor/dropbox.js'
    if fs.existsSync '../dropbox-js/lib/dropbox.min.js'
      commands.push 'cp ../dropbox-js/lib/dropbox.min.js vendor/'

    async.forEachSeries commands, run, ->
      callback() if callback

run = (args...) ->
  for a in args
    switch typeof a
      when 'string' then command = a
      when 'object'
        if a instanceof Array then params = a
        else options = a
      when 'function' then callback = a

  command += ' ' + params.join ' ' if params?
  cmd = spawn '/bin/sh', ['-c', command], options
  cmd.stdout.on 'data', (data) -> process.stdout.write data
  cmd.stderr.on 'data', (data) -> process.stderr.write data
  process.on 'SIGHUP', -> cmd.kill()
  cmd.on 'exit', (code) -> callback() if callback? and code is 0

download = ([url, file], callback) ->
  if fs.existsSync file
    callback() if callback?
    return

  run "curl -o #{file} #{url}", callback
