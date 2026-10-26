'use strict';
// IoT devices (ESP32 / Arduino with a display and a buzzer).
// One device per police post (device id = post id) and optionally one per ambulance (device id = ambulance number).
// Apps send commands -> the server keeps the latest state -> the device polls GET /api/iot/<id>/state every 1-2 seconds.
// No external packages needed.

const LIMITS = {
  BUZZ_DEFAULT_S: 20,
  BUZZ_MAX_S: 60,        // a buzzer can never be left ON for more than this (fail-safe)
  DISPLAY_DEFAULT_S: 120,
  DISPLAY_MAX_S: 600,
  ONLINE_MS: 30000,      // device polled in the last 30 s => "online"
  AUTO_REFRESH_S: 15,    // auto alert switches itself off 15 s after the last GPS update (fail-safe)
  MANUAL_HOLD_S: 60,     // after a manual command, auto mode keeps quiet for this long
};
const PATTERNS = ['beep', 'siren', 'continuous'];

const devices = new Map();
const now = () => Date.now();
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const cleanText = (v, n) => (typeof v === 'string' ? v.replace(/[^\x20-\x7E\n]/g, '').replace(/\n{3,}/g, '\n\n').trim().slice(0, n) : '');

function normId(id) {
  const s = typeof id === 'string' ? id.trim() : '';
  return /^[A-Za-z0-9_-]{2,40}$/.test(s) ? s : null;
}

function getDevice(id, create = true) {
  const key = normId(id);
  if (!key) return null;
  let d = devices.get(key);
  if (!d && create) {
    d = {
      id: key,
      display: { text: '', until: 0, by: '' },
      buzzer: { pattern: 'off', until: 0, by: '' },
      auto: true,          // alerts from the engine switch display + buzzer automatically
      autoStatus: '',      // last auto status written (approaching / imminent / test)
      holdUntil: 0,        // manual command in force => auto stays quiet
      lastSeen: 0,         // last time the DEVICE polled
      lastCommandAt: 0,
      seq: 0,              // goes up every time something changes, so a device can react only to changes
    };
    devices.set(key, d);
  }
  return d || null;
}

function view(d) {
  const t = now();
  const dispOn = d.display.text && d.display.until > t;
  const buzOn = d.buzzer.pattern !== 'off' && d.buzzer.until > t;
  return {
    id: d.id,
    online: d.lastSeen > 0 && t - d.lastSeen < LIMITS.ONLINE_MS,
    lastSeenSec: d.lastSeen ? Math.round((t - d.lastSeen) / 1000) : null,
    auto: d.auto,
    display: { text: dispOn ? d.display.text : '', on: !!dispOn, by: dispOn ? d.display.by : '', remainingSec: dispOn ? Math.round((d.display.until - t) / 1000) : 0 },
    buzzer: { pattern: buzOn ? d.buzzer.pattern : 'off', on: !!buzOn, by: buzOn ? d.buzzer.by : '', remainingSec: buzOn ? Math.round((d.buzzer.until - t) / 1000) : 0 },
    seq: d.seq,
  };
}

// What the device itself downloads. Asking for it counts as a "heartbeat" (device is online).
function deviceState(id) {
  const d = getDevice(id);
  if (!d) return null;
  d.lastSeen = now();
  const v = view(d);
  return {
    ok: true, id: d.id, seq: d.seq,
    display: { on: v.display.on, text: v.display.text },
    buzzer: { on: v.buzzer.on, pattern: v.buzzer.pattern },
    serverTime: now(),
  };
}

function getView(id) {
  const d = getDevice(id, false);
  return d ? view(d) : { id: normId(id) || String(id || ''), online: false, lastSeenSec: null, auto: true, display: { text: '', on: false, by: '', remainingSec: 0 }, buzzer: { pattern: 'off', on: false, by: '', remainingSec: 0 }, seq: 0, known: false };
}

// Manual command from an app.
// body = { display?: { text, seconds } | null,  buzzer?: { pattern: 'beep'|'siren'|'continuous'|'off', seconds },  auto?: boolean }
function command(id, body, by) {
  const d = getDevice(id);
  if (!d) { const e = new Error('Invalid device ID. Use 2-40 letters, numbers, - or _.'); e.status = 400; e.code = 'BAD_DEVICE'; throw e; }
  const b = body || {};
  const t = now();
  const who = cleanText(by || '', 40);
  let changed = false;

  if ('display' in b) {
    const x = b.display;
    const text = x && typeof x === 'object' ? cleanText(x.text, 64) : '';
    if (text) {
      const sec = clamp(Number(x.seconds) || LIMITS.DISPLAY_DEFAULT_S, 5, LIMITS.DISPLAY_MAX_S);
      d.display = { text, until: t + sec * 1000, by: who };
    } else {
      d.display = { text: '', until: 0, by: '' };
    }
    changed = true;
  }
  if ('buzzer' in b) {
    const x = b.buzzer && typeof b.buzzer === 'object' ? b.buzzer : {};
    const pattern = PATTERNS.includes(x.pattern) ? x.pattern : 'off';
    if (pattern === 'off') {
      d.buzzer = { pattern: 'off', until: 0, by: '' };
    } else {
      const sec = clamp(Number(x.seconds) || LIMITS.BUZZ_DEFAULT_S, 2, LIMITS.BUZZ_MAX_S);
      d.buzzer = { pattern, until: t + sec * 1000, by: who };
    }
    changed = true;
  }
  if (typeof b.auto === 'boolean') {
    d.auto = b.auto;
    if (!b.auto) d.autoStatus = '';
    changed = true;
  }
  if (changed) {
    d.seq += 1;
    d.lastCommandAt = t;
    if ('display' in b || 'buzzer' in b) d.holdUntil = t + LIMITS.MANUAL_HOLD_S * 1000;
  }
  return view(d);
}

function alertText(status, priority) {
  const critical = priority === 'critical';
  if (status === 'test') return 'TEST ALERT\nIOT IS WORKING';
  if (status === 'imminent') return critical ? 'CRITICAL PATIENT\nAMBULANCE CLOSE' : 'AMBULANCE CLOSE!\nCLEAR THE ROAD';
  return critical ? 'CRITICAL PATIENT\nCLEAR THE ROAD' : 'AMBULANCE COMING\nCLEAR THE ROAD';
}

// Called by the alert engine.
//  { postId, event: 'alert', status: 'approaching'|'imminent', priority }
//  { postId, event: 'test' }
//  { postId, event: 'clear' }
function onEngineEvent(ev) {
  if (!ev || !ev.postId) return;
  const d = getDevice(ev.postId, ev.event === 'clear' ? false : true);
  if (!d || !d.auto) return;
  const t = now();

  if (ev.event === 'clear') {
    if (d.autoStatus) {
      d.display = { text: '', until: 0, by: '' };
      d.buzzer = { pattern: 'off', until: 0, by: '' };
      d.autoStatus = '';
      d.seq += 1;
    }
    return;
  }
  if (t < d.holdUntil) return; // somebody just sent a manual command

  if (ev.event === 'test') {
    d.display = { text: alertText('test'), until: t + 8000, by: 'Test' };
    d.buzzer = { pattern: 'beep', until: t + 4000, by: 'Test' };
    d.autoStatus = 'test';
    d.seq += 1;
    return;
  }

  const status = ev.status === 'imminent' ? 'imminent' : 'approaching';
  const key = status + '|' + (ev.priority === 'critical' ? 'c' : 'n');
  const until = t + LIMITS.AUTO_REFRESH_S * 1000;
  if (d.autoStatus !== key) {
    d.display = { text: alertText(status, ev.priority), until, by: 'Auto' };
    d.buzzer = { pattern: status === 'imminent' ? 'siren' : 'beep', until, by: 'Auto' };
    d.autoStatus = key;
    d.seq += 1;
  } else {
    // same state: only keep it alive (no seq change)
    d.display.until = until;
    d.buzzer.until = until;
  }
}

function listDevices() {
  return [...devices.values()].map(view);
}

function reset() { devices.clear(); }

module.exports = { LIMITS, PATTERNS, normId, deviceState, getView, command, onEngineEvent, listDevices, reset };
