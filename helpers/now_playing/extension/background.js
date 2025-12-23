const HOST = "com.sketchybar.nowplaying";

let nativePort = null;
let nativeReconnectDelayMs = 1000;

function connectNativePort() {
  if (nativePort) return nativePort;
  nativePort = chrome.runtime.connectNative(HOST);
  nativeReconnectDelayMs = 1000; // reset backoff on successful connect
  nativePort.onDisconnect.addListener(() => {
    const err = chrome.runtime && chrome.runtime.lastError ? chrome.runtime.lastError : null;
    nativePort = null;
    // Exponential backoff, bounded
    const delay = nativeReconnectDelayMs;
    nativeReconnectDelayMs = Math.min(nativeReconnectDelayMs * 2, 15000);
    setTimeout(connectNativePort, delay);
  });
  nativePort.onMessage.addListener(() => {
    // No-op: native responses acknowledged silently
  });
  return nativePort;
}

function postToNativeHost(message) {
  const port = connectNativePort();
  if (!port) return;
  port.postMessage(message);
}

// Lazy-connect: we only connect when a message arrives

// Accept long-lived ports from content scripts and forward to native host
chrome.runtime.onConnect.addListener((port) => {
  if (!port || port.name !== "nowplaying") return;
  port.onMessage.addListener((msg) => {
    if (!msg || msg.type !== "nowplaying") return;
    postToNativeHost(msg);
  });
});

