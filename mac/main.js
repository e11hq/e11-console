// E11 Console for Mac — a small native window around the E11 Console server (console.e11hq.com).
// Built on each Mac by the one-line installer with tools that ship with macOS (osacompile),
// so it needs no Apple Developer account. Everything else (screens, data, updates) comes live
// from the server, so this app rarely needs reinstalling.
//
// What the app adds on top of the website: the Mac file picker, saving downloads, opening files,
// notifications with sound, a Dock badge for unread notifications, and a proper menu bar.

ObjC.import('Cocoa');
ObjC.import('WebKit');

var APP_NAME = 'E11 Console';
var fm = $.NSFileManager.defaultManager;
var HOME = ObjC.unwrap($.NSHomeDirectory());
var info = $.NSBundle.mainBundle.infoDictionary;
var SERVER = (function () {
  var v = info.objectForKey('E11ServerURL');
  return v && !v.isNil() ? ObjC.unwrap(v) : 'https://console.e11hq.com';
})();

var gWindow = null, gWebView = null, gBridge = null, gWinDelegate = null, gUIDelegate = null, gMenu = null, gMenuTarget = null;
ObjC.bindFunction('objc_msgSend', ['void', ['id', 'SEL', 'id', 'id']]);
var gPicked = {};   // token -> local file path chosen in the file picker
var gSaving = {};   // token -> path being written in Downloads

/* ---------------- helpers ---------------- */
function exists(p) { return fm.fileExistsAtPath(p); }
function ensureDir(p) { if (!exists(p)) fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(p, true, $(), null); }
function fileSize(p) {
  var a = fm.attributesOfItemAtPathError(p, null);
  if (!a || a.isNil()) return 0;
  var n = a.objectForKey('NSFileSize');
  return n && !n.isNil() ? ObjC.unwrap(n) : 0;
}
function uniquePath(dir, name) {
  name = String(name || 'file').replace(/[\/:]/g, '-');
  var dot = name.lastIndexOf('.');
  var base = dot > 0 ? name.slice(0, dot) : name, ext = dot > 0 ? name.slice(dot) : '';
  var p = dir + '/' + name, i = 2;
  while (exists(p)) { p = dir + '/' + base + ' (' + i + ')' + ext; i++; }
  return p;
}
var token = function () { return Date.now().toString(36) + Math.random().toString(36).slice(2, 8); };

/* ---------------- commands from the page ---------------- */
var commands = {
  // Mac file picker; returns tokens so the page can read the files in pieces and upload them
  pickLocalFiles: function (a) {
    var panel = $.NSOpenPanel.openPanel;
    $.NSApp.activateIgnoringOtherApps(true);
    try { panel.collectionBehavior = (1 << 1) | (1 << 8); } catch (e) { /* ignore */ }
    panel.canChooseFiles = true;
    panel.canChooseDirectories = false;
    panel.allowsMultipleSelection = a.multiple !== false;
    if (a.images) { try { panel.allowedFileTypes = $(['png', 'jpg', 'jpeg', 'heic', 'gif', 'webp', 'tif', 'tiff', 'bmp', 'svg']); } catch (e) { /* ignore */ } }
    panel.prompt = a.prompt || 'Choose';
    if (a.message) panel.message = a.message;
    if (Number(panel.runModal) !== 1) return { ok: true, files: [] };
    var urls = panel.URLs, out = [];
    for (var i = 0; i < urls.count; i++) {
      var p = ObjC.unwrap(urls.objectAtIndex(i).path);
      var t = token();
      gPicked[t] = p;
      out.push({ token: t, name: p.split('/').pop(), size: fileSize(p) });
    }
    return { ok: true, files: out };
  },
  readLocalChunk: function (a) {
    var p = gPicked[a.token];
    if (!p) return { ok: false, error: 'File no longer available' };
    var fh = $.NSFileHandle.fileHandleForReadingAtPath(p);
    if (!fh || fh.isNil()) return { ok: false, error: 'Could not read ' + p.split('/').pop() };
    fh.seekToFileOffset(Number(a.offset) || 0);
    var data = fh.readDataOfLength(Number(a.length) || 0);
    fh.closeFile;
    if (a.last) delete gPicked[a.token];
    return { ok: true, b64: ObjC.unwrap(data.base64EncodedStringWithOptions(0)) };
  },
  // Save a download in pieces: into Downloads (and show it), or a temporary folder (and open it)
  saveFile: function (a) {
    var dest = gSaving[a.token];
    var data = $.NSData.alloc.initWithBase64EncodedStringOptions($(String(a.b64 || '')), 0);
    if (!dest) {
      var dir = a.open ? ObjC.unwrap($.NSTemporaryDirectory()) + 'E11 Console' : HOME + '/Downloads';
      ensureDir(dir);
      dest = uniquePath(dir, a.name);
      fm.createFileAtPathContentsAttributes(dest, data, $());
      gSaving[a.token] = dest;
    } else {
      var h = $.NSFileHandle.fileHandleForWritingAtPath(dest);
      h.seekToEndOfFile; h.writeData(data); h.closeFile;
    }
    if (a.done) {
      delete gSaving[a.token];
      if (a.open) $.NSWorkspace.sharedWorkspace.openURL($.NSURL.fileURLWithPath(dest));
      else $.NSWorkspace.sharedWorkspace.selectFileInFileViewerRootedAtPath(dest, '');
    }
    return { ok: true, path: dest };
  },
  openURL: function (a) {
    var u = String(a.url || '');
    if (!/^(https?|mailto):/i.test(u)) return { ok: false, error: 'Only web links can be opened' };
    $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(u));
    return { ok: true };
  },
  notify: function (a) {
    if (a.banner !== false) {
      try {
        var sa = Application.currentApplication();
        sa.includeStandardAdditions = true;
        sa.displayNotification(String(a.body || ''), { withTitle: String(a.title || APP_NAME), subtitle: String(a.subtitle || '') });
      } catch (e) { /* notifications off */ }
    }
    if (a.sound) { try { var s = $.NSSound.soundNamed(String(a.sound)); if (s && !s.isNil()) s.play; } catch (e) { /* ignore */ } }
    return { ok: true };
  },
  badge: function (a) { $.NSApp.dockTile.badgeLabel = a.n ? String(a.n) : ''; return { ok: true }; },
  setAppearance: function (a) {
    var light = a.mode === 'light';
    if (gWindow) {
      gWindow.appearance = $.NSAppearance.appearanceNamed(light ? 'NSAppearanceNameAqua' : 'NSAppearanceNameDarkAqua');
      gWindow.backgroundColor = light ? $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.965, 0.965, 0.973, 1) : $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.043, 0.043, 0.047, 1);
    }
    return { ok: true };
  },
  appInfo: function () { return { ok: true, server: SERVER, version: ObjC.unwrap(info.objectForKey('CFBundleShortVersionString')) }; },
};

// Answer the page by calling window.__e11NativeReply(id, result) inside it
function reply(id, res) {
  var js = 'window.__e11NativeReply && window.__e11NativeReply(' + JSON.stringify(id) + ',' + JSON.stringify(res) + ')';
  // Sent through objc_msgSend with an exact signature, so WebKit gets a real nil completion
  // handler and nothing is returned. (A JavaScript completion handler, or performSelector, makes
  // the macOS scripting bridge crash — tested on a Mac on 2026-10-20.)
  try { $.objc_msgSend(gWebView, 'evaluateJavaScript:completionHandler:', $(js), $()); } catch (e) { /* page gone */ }
}
function handleMessage(raw) {
  var msg;
  try { msg = JSON.parse(raw); } catch (e) { return; }
  var res;
  try {
    var fn = commands[msg.cmd];
    res = fn ? fn(msg.args || {}) : { ok: false, error: 'Unknown command ' + msg.cmd };
  } catch (e) { res = { ok: false, error: String(e && e.message ? e.message : e) }; }
  reply(msg.id, res);
}

/* ---------------- Objective-C classes ---------------- */
// Some macOS versions can't look up a protocol by name (e.g. WKUIDelegate) until WebKit has used it,
// which stops the app with "protocol does not exist". The protocol list is only a declaration —
// WebKit checks which methods exist — so if it fails, register the class without it.
function registerClass(def) {
  try { ObjC.registerSubclass(def); return; } catch (e) { /* try without protocols */ }
  var copy = { name: def.name, superclass: def.superclass, methods: def.methods };
  ObjC.registerSubclass(copy);
}
registerClass({
  name: 'E11ClientBridge',
  superclass: 'NSObject',
  protocols: ['WKScriptMessageHandler'],
  methods: {
    'userContentController:didReceiveScriptMessage:': {
      types: ['void', ['id', 'id']],
      implementation: function (controller, message) { handleMessage(ObjC.unwrap(message.body)); },
    },
  },
});

// Links that open a new window (target=_blank) go to the default browser
registerClass({
  name: 'E11ClientUIDelegate',
  superclass: 'NSObject',
  protocols: ['WKUIDelegate'],
  methods: {
    'webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:': {
      types: ['id', ['id', 'id', 'id', 'id']],
      implementation: function (webView, config, action, features) {
        try { var u = action.request.URL; if (u && !u.isNil()) $.NSWorkspace.sharedWorkspace.openURL(u); } catch (e) { /* ignore */ }
        return null;
      },
    },
  },
});

registerClass({
  name: 'E11ClientWindowDelegate',
  superclass: 'NSObject',
  protocols: ['NSWindowDelegate'],
  methods: {
    'windowWillClose:': {
      types: ['void', ['id']],
      implementation: function () { $.NSApp.performSelectorWithObjectAfterDelay('terminate:', null, 0.6); },
    },
  },
});

// Menu actions that need the web view
registerClass({
  name: 'E11ClientMenuTarget',
  superclass: 'NSObject',
  methods: {
    'reloadPage:': { types: ['void', ['id']], implementation: function () { if (gWebView) gWebView.reload; } },
    'goHome:': { types: ['void', ['id']], implementation: function () { if (gWebView) gWebView.loadRequest($.NSURLRequest.requestWithURL($.NSURL.URLWithString(SERVER + '/'))); } },
    'openInBrowser:': { types: ['void', ['id']], implementation: function () { $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(SERVER + '/')); } },
    'zoomIn:': { types: ['void', ['id']], implementation: function () { if (gWebView) gWebView.pageZoom = Math.min(2, gWebView.pageZoom + 0.1); } },
    'zoomOut:': { types: ['void', ['id']], implementation: function () { if (gWebView) gWebView.pageZoom = Math.max(0.6, gWebView.pageZoom - 0.1); } },
    'zoomReset:': { types: ['void', ['id']], implementation: function () { if (gWebView) gWebView.pageZoom = 1; } },
  },
});

/* ---------------- Menu bar ---------------- */
function item(title, action, key, mask, target) {
  var it = $.NSMenuItem.alloc.initWithTitleActionKeyEquivalent(title, action, key || '');
  if (mask !== undefined) it.keyEquivalentModifierMask = mask;
  if (target) it.target = target;
  return it;
}
function buildMenu() {
  var CMD = 1 << 20, SHIFT = 1 << 17, OPT = 1 << 19;
  gMenuTarget = $.E11ClientMenuTarget.alloc.init;
  gMenu = $.NSMenu.alloc.initWithTitle('Main');

  var appItem = $.NSMenuItem.alloc.init, appMenu = $.NSMenu.alloc.initWithTitle(APP_NAME);
  appMenu.addItem(item('About ' + APP_NAME, 'orderFrontStandardAboutPanel:', ''));
  appMenu.addItem($.NSMenuItem.separatorItem);
  appMenu.addItem(item('Hide ' + APP_NAME, 'hide:', 'h'));
  appMenu.addItem(item('Hide Others', 'hideOtherApplications:', 'h', CMD | OPT));
  appMenu.addItem(item('Show All', 'unhideAllApplications:', ''));
  appMenu.addItem($.NSMenuItem.separatorItem);
  appMenu.addItem(item('Quit ' + APP_NAME, 'terminate:', 'q'));
  appItem.submenu = appMenu; gMenu.addItem(appItem);

  var editItem = $.NSMenuItem.alloc.init, editMenu = $.NSMenu.alloc.initWithTitle('Edit');
  editMenu.addItem(item('Undo', 'undo:', 'z'));
  editMenu.addItem(item('Redo', 'redo:', 'z', CMD | SHIFT));
  editMenu.addItem($.NSMenuItem.separatorItem);
  editMenu.addItem(item('Cut', 'cut:', 'x'));
  editMenu.addItem(item('Copy', 'copy:', 'c'));
  editMenu.addItem(item('Paste', 'paste:', 'v'));
  editMenu.addItem(item('Select All', 'selectAll:', 'a'));
  editItem.submenu = editMenu; gMenu.addItem(editItem);

  var viewItem = $.NSMenuItem.alloc.init, viewMenu = $.NSMenu.alloc.initWithTitle('View');
  viewMenu.addItem(item('Reload', 'reloadPage:', 'r', CMD, gMenuTarget));
  viewMenu.addItem(item('Go to Home', 'goHome:', 'h', CMD | SHIFT, gMenuTarget));
  viewMenu.addItem($.NSMenuItem.separatorItem);
  viewMenu.addItem(item('Actual Size', 'zoomReset:', '0', CMD, gMenuTarget));
  viewMenu.addItem(item('Zoom In', 'zoomIn:', '+', CMD, gMenuTarget));
  viewMenu.addItem(item('Zoom Out', 'zoomOut:', '-', CMD, gMenuTarget));
  viewMenu.addItem($.NSMenuItem.separatorItem);
  viewMenu.addItem(item('Open in Browser', 'openInBrowser:', '', undefined, gMenuTarget));
  viewItem.submenu = viewMenu; gMenu.addItem(viewItem);

  var winItem = $.NSMenuItem.alloc.init, winMenu = $.NSMenu.alloc.initWithTitle('Window');
  winMenu.addItem(item('Minimize', 'performMiniaturize:', 'm'));
  winMenu.addItem(item('Zoom', 'performZoom:', ''));
  winMenu.addItem(item('Enter Full Screen', 'toggleFullScreen:', 'f', CMD | (1 << 18)));
  winMenu.addItem($.NSMenuItem.separatorItem);
  winMenu.addItem(item('Close Window', 'performClose:', 'w'));
  winItem.submenu = winMenu; gMenu.addItem(winItem);

  $.NSApp.mainMenu = gMenu;
  $.NSApp.windowsMenu = winMenu;
}

/* ---------------- Window ---------------- */
function buildWindow() {
  var style = 1 | 2 | 4 | 8;
  gWindow = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, 1320, 840), style, 2, false);
  gWindow.releasedWhenClosed = false;
  gWindow.title = APP_NAME;
  gWindow.titlebarAppearsTransparent = true;
  gWindow.appearance = $.NSAppearance.appearanceNamed('NSAppearanceNameDarkAqua');
  gWindow.backgroundColor = $.NSColor.colorWithSRGBRedGreenBlueAlpha(0.043, 0.043, 0.047, 1);
  gWindow.minSize = $.NSMakeSize(960, 620);
  gWindow.center;
  gWindow.setFrameAutosaveName('E11ConsoleClientWindow');
  gWinDelegate = $.E11ClientWindowDelegate.alloc.init;
  gWindow.delegate = gWinDelegate;

  var config = $.WKWebViewConfiguration.alloc.init;
  config.websiteDataStore = $.WKWebsiteDataStore.defaultDataStore; // stay signed in between launches
  gBridge = $.E11ClientBridge.alloc.init;
  config.userContentController.addScriptMessageHandlerName(gBridge, 'e11');

  gWebView = $.WKWebView.alloc.initWithFrameConfiguration(gWindow.contentView.bounds, config);
  gWebView.autoresizingMask = 2 | 16;
  gUIDelegate = $.E11ClientUIDelegate.alloc.init;
  gWebView.UIDelegate = gUIDelegate;
  try { gWebView.setValueForKey($.NSNumber.numberWithBool(false), 'drawsBackground'); } catch (e) { /* optional */ }
  try { gWebView.inspectable = true; } catch (e) { /* macOS 13.3+ */ }
  gWindow.contentView.addSubview(gWebView);
  gWebView.loadRequest($.NSURLRequest.requestWithURL($.NSURL.URLWithString(SERVER + '/')));

  gWindow.makeKeyAndOrderFront(null);
  $.NSApp.activateIgnoringOtherApps(true);
}

function run() {
  try { buildMenu(); buildWindow(); }
  catch (e) {
    var app = Application.currentApplication();
    app.includeStandardAdditions = true;
    app.displayAlert('E11 Console could not start', { message: String(e), as: 'critical' });
    $.NSApp.terminate(null);
  }
}
function reopen() { if (gWindow) gWindow.makeKeyAndOrderFront(null); }
