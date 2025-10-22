function readSession() {
  const md = navigator.mediaSession && navigator.mediaSession.metadata;
  const title = md && md.title || document.title || "";
  const artist = md && md.artist || "";
  const album = md && md.album || "";
  const state = (navigator.mediaSession && navigator.mediaSession.playbackState) || "paused";
  let duration = 0, elapsed = 0;
  try {
    const a = document.querySelector('audio, video');
    if (a) { duration = a.duration || 0; elapsed = a.currentTime || 0; }
  } catch {}
  return { type: "nowplaying", app: "YouTube Music", title, artist, album, state, duration, elapsed };
}

let bgPort = null;
let reconnectDelayMs = 1000;

function connectBackgroundPort() {
  if (!chrome || !chrome.runtime || !chrome.runtime.connect || !chrome.runtime.id) {
    const delay = reconnectDelayMs;
    reconnectDelayMs = Math.min(reconnectDelayMs * 2, 15000);
    setTimeout(connectBackgroundPort, delay);
    return;
  }
  try {
    bgPort = chrome.runtime.connect({ name: "nowplaying" });
    reconnectDelayMs = 1000; // reset backoff
    bgPort.onDisconnect.addListener(() => {
      bgPort = null;
      const delay = reconnectDelayMs;
      reconnectDelayMs = Math.min(reconnectDelayMs * 2, 15000);
      setTimeout(connectBackgroundPort, delay);
    });
  } catch (_e) {
    bgPort = null;
    const delay = reconnectDelayMs;
    reconnectDelayMs = Math.min(reconnectDelayMs * 2, 15000);
    setTimeout(connectBackgroundPort, delay);
  }
}

function sendUpdate() {
  const p = bgPort;
  if (!p) return;
  p.postMessage(readSession());
}

// Hook MediaSession updates
if (navigator.mediaSession) {
  const orig = navigator.mediaSession.metadata;
  const observer = new MutationObserver(sendUpdate);
  try {
    const a = document.querySelector('audio, video');
    if (a) {
      a.addEventListener('timeupdate', sendUpdate);
      a.addEventListener('play', sendUpdate);
      a.addEventListener('pause', sendUpdate);
    }
  } catch {}
}

connectBackgroundPort();

let iv = setInterval(sendUpdate, 1000);
document.addEventListener('visibilitychange', () => {
  if (document.hidden) { clearInterval(iv); }
  else { iv = setInterval(sendUpdate, 1000); sendUpdate(); }
});
sendUpdate();


