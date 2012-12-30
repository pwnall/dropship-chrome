# Sample dropbox.js Chrome Extension

This is a demonstration of using dropbox.js, the client library for the Dropbox
API, inside a Google Chrome browser extension.


## Development

### Dev Environment Setup

Install [node.js](http://nodejs.org/#download) to get `npm` (the node
package manager), then use it to install the libraries required by the build
process.

```bash
git clone https://github.com/pwnall/dropship-chrome.git
cd dropship-chrome
npm install
```

### Build

Run `cake build` and ignore any deprecation warnings that might come up.


```bash
cake build
```

### Install

Follow the steps below to install the development version of the extension. You
only need to do this once.

1. Type `chrome://extensions` in Chrome's address bar and press _Enter_.
1. Check the `Developer mode` checkbox.
1. Press the `Load unpacked extension...` button.
1. Navigate to the `build/` directory inside the extension and select it.

Once the extension is installed, follow the steps below to reload it after a
rebuild.

1. Right-click the Dropbox icon.
1. Select `Manage Extensions...` from the pop-up menu.
1. Click the `Reload` link under the Dropbox extension.

### Test

This extension uses manual testing for now.


## Copyright and License

The extension is Copyright (c) 2012 Victor Costan, and distributed under the
MIT license.
