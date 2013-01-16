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
  for dir in ['build', 'build/css', 'build/font', 'build/html', 'build/images',
              'build/js', 'build/vendor', 'build/vendor/font',
              'build/vendor/js']
    fs.mkdirSync dir unless fs.existsSync dir

  commands = []
  commands.push 'cp src/manifest.json build/'
  commands.push 'cp -r src/html build/'
  commands.push 'cp -r src/font build/'
  # TODO(pwnall): consider optipng
  commands.push 'cp -r src/images build/'
  for inFile in glob.sync 'src/less/**/*.less'
    continue if path.basename(inFile).match /^_/
    outFile = inFile.replace(/^src\/less\//, 'build/css/').
                     replace(/\.less$/, '.css')
    commands.push "node_modules/less/bin/lessc --strict-imports #{inFile} " +
                  "> #{outFile}"
  for inFile in glob.sync 'vendor/js/*.js'
    continue if inFile.match /\.min\.js$/
    outFile = 'build/' + inFile
    commands.push "cp #{inFile} #{outFile}"
  for inFile in glob.sync 'vendor/font/*'
    outFile = 'build/' + inFile
    commands.push "cp #{inFile} #{outFile}"
  commands.push 'node_modules/coffee-script/bin/coffee --output build/js ' +
                '--compile src/coffee/*.coffee'
  async.forEachSeries commands, run, ->
    callback() if callback

release = (callback) ->
  for dir in ['release', 'release/css', 'release/html', 'release/images',
              'release/js', 'release/vendor', 'release/vendor/font',
              'release/vendor/js']
    fs.mkdirSync dir unless fs.existsSync dir

  if fs.existsSync 'release/dropship-chrome.zip'
    fs.unlinkSync 'release/dropship-chrome.zip'

  commands = []
  commands.push 'cp build/manifest.json release/'
  # TODO(pwnall): consider a html minifier
  commands.push 'cp -r build/html release/'
  commands.push 'cp -r build/font release/'
  commands.push 'cp -r build/images release/'
  commands.push 'cp -r build/vendor/font release/vendor/'
  for inFile in glob.sync 'src/less/**/*.less'
    continue if path.basename(inFile).match /^_/
    outFile = inFile.replace(/^src\/less\//, 'release/css/').
                     replace(/\.less$/, '.css')
    commands.push "node_modules/less/bin/lessc --compress --strict-imports " +
                  "#{inFile} > #{outFile}"
  for inFile in glob.sync 'build/js/*.js'
    outFile = inFile.replace /^build\//, 'release/'
    commands.push 'node_modules/uglify-js/bin/uglifyjs --compress --mangle ' +
                  "--output #{outFile} #{inFile}"
  for inFile in glob.sync 'vendor/js/*.min.js'
    outFile = 'release/' + inFile.replace /\.min\.js$/, '.js'
    commands.push "cp #{inFile} #{outFile}"

  commands.push 'cd release && zip -r -9 -x "*.DS_Store" "*.sw*" @ ' +
                'dropship-chrome.zip .'

  async.forEachSeries commands, run, ->
    callback() if callback

clean = (callback) ->
  remove 'build', ignoreMissing: true, ->
    remove 'release', ignoreMissing: true,
      callback

vendor = (callback) ->
  dirs = ['vendor', 'vendor/js', 'vendor/less', 'vendor/font', 'vendor/tmp']
  for dir in dirs
    fs.mkdirSync dir unless fs.existsSync dir

  downloads = [
    ['https://cdnjs.cloudflare.com/ajax/libs/dropbox.js/0.8.1/dropbox.min.js',
     'vendor/js/dropbox.min.js'],

    # Zepto.js is a small subset of jQuery.
    ['http://zeptojs.com/zepto.js', 'vendor/js/zepto.js'],
    ['http://zeptojs.com/zepto.min.js', 'vendor/js/zepto.min.js'],

    # Humanize for user-readable sizes.
    ['https://raw.github.com/taijinlee/humanize/0a97f11503e3844115cfa3dc365cf9884e150e4b/humanize.js',
     'vendor/js/humanize.js'],

    # FontAwesome for icons.
    ['https://github.com/FortAwesome/Font-Awesome/archive/v3.0.1.zip',
     'vendor/tmp/font_awesome.zip'],
  ]

  async.forEachSeries downloads, download, ->
    # If a dropbox-js development tree happens to be checked out next to
    # the extension, copy the dropbox.js files from there.
    commands = []
    if fs.existsSync '../dropbox-js/lib/dropbox.js'
      commands.push 'cp ../dropbox-js/lib/dropbox.js vendor/js/'
    else
      # If there is no development dir, use the minified dropbox.js everywhere.
      unless fs.existsSync 'vendor/dropbox.js'
        commands.push 'cp vendor/js/dropbox.min.js vendor/js/dropbox.js'
    if fs.existsSync '../dropbox-js/lib/dropbox.min.js'
      commands.push 'cp ../dropbox-js/lib/dropbox.min.js vendor/js/'

    # Minify humanize.
    unless fs.existsSync 'vendor/js/humanize.min.js'
      commands.push 'node_modules/uglify-js/bin/uglifyjs --compress ' +
          '--mangle --output vendor/js/humanize.min.js vendor/js/humanize.js'

    # Unpack fontawesome.
    unless fs.existsSync 'vendor/tmp/Font-Awesome-3.0.1/'
      commands.push 'unzip -qq -d vendor/tmp vendor/tmp/font_awesome'
      # Patch fontawesome inplace.
      commands.push 'sed -i -e "/^@FontAwesomePath:/d" ' +
                    'vendor/tmp/Font-Awesome-3.0.1/less/font-awesome.less'

    async.forEachSeries commands, run, ->
      commands = []

      # Copy fontawesome to vendor/.
      for inFile in glob.sync 'vendor/tmp/Font-Awesome-3.0.1/less/*.less'
        outFile = inFile.replace /^vendor\/tmp\/Font-Awesome-3\.0\.1\/less\//,
                                 'vendor/less/'
        unless fs.existsSync outFile
          commands.push "cp #{inFile} #{outFile}"
      for inFile in glob.sync 'vendor/tmp/Font-Awesome-3.0.1/font/*'
        outFile = inFile.replace /^vendor\/tmp\/Font-Awesome-3\.0\.1\/font\//,
                                 'vendor/font/'
        unless fs.existsSync outFile
          commands.push "cp #{inFile} #{outFile}"

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

  run "curl -L -o #{file} #{url}", callback
