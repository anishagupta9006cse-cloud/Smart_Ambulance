'use strict';
// Core alert logic: trips, police posts, forward-only alerts, auto-mute. No network deps.
const { projectOnRoute, routeSlice } = require('./geo');

const CFG = {
  ALERT_DIST: Number(process.env.ALERT_DISTANCE_M) || 1500, // "approaching" at this distance ahead
  IMMINENT_DIST: 400,
  STANDBY_DIST: 8000,
  PASS_MARGIN: 30,          // metres past the post => passed
  STALE_MS: 20000,          // no GPS for 20s => automation paused
  PASSED_KEEP_MS: 20000,    // show "passed" then auto-mute
  TEST_ALERT_MS: 20000,
  OFF_ROUTE_M: 80,
  ARRIVE_M: 40,
  TRIP_IDLE_END_MS: 10 * 60 * 1000,
  TRIP_KEEP_MS: 30 * 60 * 1000,
  POST_STALE_MS: (Number(process.env.POST_STALE_SECONDS) || 180) * 1000, // police phone silent this long => post is offline
};

const posts = new Map();
const trips = new Map();
const tests = new Map(); // postId -> { tripId, until }
const events = [];
let notifier = () => {};
let persist = { post() {}, tripEnd() {} }; // filled by server.js (saves to the database)

const now = () => Date.now();
const rid = (p) => p + Math.random().toString(36).slice(2, 8).toUpperCase();
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const clean = (v, n) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, n) : '');

function httpError(status, message, code) {
  const e = new Error(message);
  e.status = status;
  e.code = code || 'ERROR';
  return e;
}
function validPoint(lat, lng) {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
}
function logEvent(type, data) {
  events.push({ t: now(), type, ...data });
  if (events.length > 500) events.splice(0, events.length - 500);
}
function setNotifier(fn) { notifier = typeof fn === 'function' ? fn : () => {}; }
function setPersist(p) { persist = { ...persist, ...p }; }
function loadPosts(list) {
  for (const p of list || []) {
    if (p && p.id && validPoint(Number(p.lat), Number(p.lng))) posts.set(p.id, { ...p, lastSeen: 0 }); // offline until the police app connects again
  }
}
function allPosts() { return [...posts.values()]; }
function deletePost(id) { return posts.delete(id); }
function tripSummary(trip) {
  return {
    id: trip.id, ambulanceId: trip.ambulanceId, driverName: trip.driverName, destination: trip.destName,
    startedAt: trip.startedAt, endedAt: trip.endedAt || now(), status: trip.status,
    distance: Math.round(trip.route.total), travelled: Math.round(trip.chain),
  };
}
function recordTripEnd(trip) { try { persist.tripEnd(tripSummary(trip)); } catch (_) {} }

// ---------------- posts ----------------
function upsertPost(b) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!validPoint(lat, lng)) throw httpError(400, 'Invalid post location.', 'BAD_LOCATION');
  const id = typeof b.id === 'string' && /^[A-Za-z0-9_-]{4,40}$/.test(b.id) ? b.id : rid('P');
  const old = posts.get(id);
  const post = {
    id,
    name: clean(b.name, 60) || 'Police Post',
    area: clean(b.area, 80),
    officer: clean(b.officer, 40),
    lat, lng,
    radius: clamp(Number(b.radius) || 500, 100, 3000),
    onDuty: true,
    lastSeen: now(),
    registeredAt: old ? old.registeredAt : now(),
  };
  posts.set(id, post);
  try { persist.post(post); } catch (_) {}
  logEvent('post_registered', { postId: id, name: post.name });
  return post;
}
function setOffDuty(postId) {
  const p = posts.get(postId);
  if (p) { p.onDuty = false; try { persist.post(p); } catch (_) {} logEvent('post_offduty', { postId }); }
}

// ---------------- trips ----------------
function startTrip({ driverName, ambulanceId, from, to, routeData, destinationName }) {
  for (const t of trips.values()) {
    if (t.active && t.ambulanceId === ambulanceId) { t.active = false; t.status = 'stopped'; t.endedAt = now(); recordTripEnd(t); }
  }
  const t0 = now();
  const trip = {
    id: rid('T'),
    driverName, ambulanceId, from, to,
    destName: destinationName || '',
    route: routeData.route,
    junctions: routeData.junctions,
    distance: routeData.distance,
    duration: routeData.duration,
    fallback: !!routeData.fallback,
    startedAt: t0, lastUpdate: t0, endedAt: 0,
    active: true, status: 'ok',
    pos: from, speed: 0, chain: 0, lastIdx: 0,
    offRoute: false, offRouteCount: 0,
    postState: {}, postInfoCache: {},
  };
  trips.set(trip.id, trip);
  logEvent('trip_started', { tripId: trip.id, ambulanceId });
  return trip;
}

function getTrip(id) {
  const t = trips.get(id);
  if (!t) throw httpError(404, 'Trip not found on the server.', 'TRIP_NOT_FOUND');
  return t;
}
function getPS(trip, postId) {
  if (!trip.postState[postId]) trip.postState[postId] = { seen: false, passedAt: 0, actions: [] };
  return trip.postState[postId];
}

function postRouteInfo(trip, post) {
  const key = `${post.lat},${post.lng},${post.radius}`;
  const c = trip.postInfoCache[post.id];
  if (c && c.key === key) return c.val;
  const pr = projectOnRoute(trip.route, post);
  const val = { onRoute: pr.dist <= post.radius, chain: pr.chain, dist: pr.dist };
  trip.postInfoCache[post.id] = { key, val };
  return val;
}

// status of one post relative to one trip (null = not relevant)
function evalPost(trip, post, t) {
  if (!post.onDuty || t - post.lastSeen > CFG.POST_STALE_MS) return null; // off duty or phone offline
  const info = postRouteInfo(trip, post);
  if (!info.onRoute) return null;
  const ps = getPS(trip, post.id);
  const distAhead = info.chain - trip.chain;
  if (ps.passedAt) {
    return { status: t - ps.passedAt > CFG.PASSED_KEEP_MS ? 'expired' : 'passed', distAhead, info, ps };
  }
  if (distAhead < -CFG.PASS_MARGIN) return { status: 'expired', distAhead, info, ps }; // passed before it was ever alerted
  let status;
  if (distAhead <= CFG.IMMINENT_DIST) status = 'imminent';
  else if (distAhead <= CFG.ALERT_DIST) status = 'approaching';
  else if (distAhead <= CFG.STANDBY_DIST) status = 'standby';
  else status = 'far';
  if ((status === 'imminent' || status === 'approaching') && (trip.offRoute || t - trip.lastUpdate > CFG.STALE_MS)) {
    status = 'paused'; // fail-safe: stale GPS / route deviation
  }
  return { status, distAhead, info, ps };
}

function etaSeconds(trip, metres) {
  const avg = trip.duration > 0 ? trip.route.total / trip.duration : 8;
  const mps = trip.speed > 3 ? trip.speed : Math.max(avg, 5);
  return Math.round(Math.max(0, metres) / mps);
}

function notifyPosts(trip) {
  const t = now();
  for (const post of posts.values()) {
    const ev = evalPost(trip, post, t);
    if (ev && ev.status !== 'far') notifier({ room: 'post:' + post.id, event: 'refresh' });
  }
}

function updateLocation(tripId, b) {
  const trip = getTrip(tripId);
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!validPoint(lat, lng)) throw httpError(400, 'Invalid GPS location.', 'BAD_LOCATION');
  if (!trip.active) return tripView(trip);
  const t = now();
  const p = { lat, lng };
  trip.pos = p;
  trip.speed = Math.max(0, Number(b.speed) || 0);
  trip.lastUpdate = t;

  let proj = projectOnRoute(trip.route, p, Math.max(0, trip.lastIdx - 3), trip.lastIdx + 400);
  if (proj.dist > CFG.OFF_ROUTE_M) {
    const full = projectOnRoute(trip.route, p);
    if (full.dist <= CFG.OFF_ROUTE_M) proj = full;
  }
  if (proj.dist <= CFG.OFF_ROUTE_M) {
    trip.offRoute = false;
    trip.offRouteCount = 0;
    trip.lastIdx = proj.idx;
    if (proj.chain > trip.chain) trip.chain = proj.chain; // forward-only progress
  } else {
    trip.offRouteCount += 1;
    if (trip.offRouteCount >= 3) trip.offRoute = true;
  }

  if (!trip.offRoute) {
    for (const post of posts.values()) {
      const ev = evalPost(trip, post, t);
      if (!ev) continue;
      const ps = ev.ps;
      if (ev.status === 'approaching' || ev.status === 'imminent') {
        if (!ps.seen) { ps.seen = true; logEvent('alert_dispatched', { tripId, postId: post.id }); }
      }
      if (ps.seen && !ps.passedAt && ev.distAhead < -CFG.PASS_MARGIN) {
        ps.passedAt = t;
        logEvent('post_passed_automute', { tripId, postId: post.id });
      }
    }
    if (trip.route.total - trip.chain < CFG.ARRIVE_M) {
      trip.active = false; trip.status = 'completed'; trip.endedAt = t;
      recordTripEnd(trip);
      logEvent('trip_completed', { tripId });
    }
  }
  notifyPosts(trip);
  return tripView(trip);
}

function stopTrip(tripId) {
  const trip = getTrip(tripId);
  if (trip.active) { trip.active = false; trip.status = 'stopped'; trip.endedAt = now(); recordTripEnd(trip); logEvent('trip_stopped', { tripId }); }
  for (const post of posts.values()) notifier({ room: 'post:' + post.id, event: 'refresh' });
  return trip;
}

function replaceRoute(trip, routeData, newFrom) {
  trip.route = routeData.route;
  trip.junctions = routeData.junctions;
  trip.distance = routeData.distance;
  trip.duration = routeData.duration;
  trip.fallback = !!routeData.fallback;
  trip.from = newFrom;
  trip.chain = 0; trip.lastIdx = 0;
  trip.offRoute = false; trip.offRouteCount = 0;
  trip.postInfoCache = {};
  for (const ps of Object.values(trip.postState)) { ps.seen = false; ps.passedAt = 0; }
  logEvent('trip_rerouted', { tripId: trip.id });
}

function nextJunction(trip) {
  const j = trip.junctions.find((x) => x.chain > trip.chain + 5);
  if (!j) return null;
  return { id: j.id, name: j.name, lat: j.lat, lng: j.lng, distance: Math.round(j.chain - trip.chain) };
}

function tripView(trip) {
  const t = now();
  const remaining = Math.max(0, trip.route.total - trip.chain);
  const postsView = [];
  const actions = [];
  for (const post of posts.values()) {
    const ev = evalPost(trip, post, t);
    if (!ev || ev.status === 'expired') continue;
    postsView.push({
      id: post.id, name: post.name, lat: post.lat, lng: post.lng, radius: post.radius,
      distAhead: Math.round(ev.distAhead), status: ev.status,
      acked: ev.ps.actions.some((a) => a.action === 'ack'),
    });
  }
  for (const [pid, ps] of Object.entries(trip.postState)) {
    const post = posts.get(pid);
    for (const a of ps.actions) actions.push({ postName: post ? post.name : pid, action: a.action, at: a.at });
  }
  actions.sort((a, b) => b.at - a.at);
  let status = 'ok';
  if (!trip.active) status = trip.status === 'completed' ? 'completed' : 'stopped';
  else if (trip.offRoute) status = 'off_route';
  return {
    ok: true, status,
    chain: Math.round(trip.chain), total: Math.round(trip.route.total),
    remaining: Math.round(remaining), etaSec: etaSeconds(trip, remaining),
    nextJunction: nextJunction(trip),
    posts: postsView,
    actions: actions.slice(0, 8),
    serverTime: t,
  };
}

// ---------------- police side ----------------
function alertObject(trip, post, ev, status, isTest) {
  const t = now();
  const distAhead = Math.max(0, Math.round(ev ? ev.distAhead : 0));
  const info = ev ? ev.info : postRouteInfo(trip, post);
  const actions = ev ? ev.ps.actions : (trip.postState[post.id] ? trip.postState[post.id].actions : []);
  return {
    tripId: trip.id, ambulanceId: trip.ambulanceId, driverName: trip.driverName,
    status, test: !!isTest,
    distAhead, etaSec: etaSeconds(trip, distAhead),
    amb: { lat: trip.pos.lat, lng: trip.pos.lng },
    destination: trip.destName,
    route: status === 'passed' ? [] : routeSlice(trip.route, Math.max(0, trip.chain - 50), info.chain + 100).map((p) => [p.lat, p.lng]),
    acked: actions.some((a) => a.action === 'ack'),
    actions: actions.slice(-6).map((a) => ({ action: a.action, at: a.at, officer: a.officer || '' })),
    updatedAt: trip.lastUpdate,
    gpsAgeSec: Math.round((t - trip.lastUpdate) / 1000),
  };
}

function alertsForPost(postId) {
  const post = posts.get(postId);
  if (!post) throw httpError(404, 'Post is not registered.', 'POST_NOT_FOUND');
  const t = now();
  post.lastSeen = t;
  const out = [];
  if (post.onDuty) {
    for (const trip of trips.values()) {
      if (!trip.active) continue;
      const ev = evalPost(trip, post, t);
      if (!ev || ev.status === 'far' || ev.status === 'expired') continue;
      out.push(alertObject(trip, post, ev, ev.status, false));
    }
    const te = tests.get(postId);
    if (te && te.until > t) {
      const trip = trips.get(te.tripId);
      if (trip) out.push(alertObject(trip, post, null, 'test', true));
    }
  }
  out.sort((a, b) => a.distAhead - b.distAhead);
  return { ok: true, serverTime: t, post: { id: post.id, name: post.name, onDuty: post.onDuty }, alerts: out };
}

function testAlert(trip) {
  const t = now();
  const all = [...posts.values()].filter((p) => p.onDuty && t - p.lastSeen < CFG.POST_STALE_MS);
  const onRoute = all.filter((p) => postRouteInfo(trip, p).onRoute);
  const targets = onRoute.length ? onRoute : all;
  for (const p of targets) {
    tests.set(p.id, { tripId: trip.id, until: t + CFG.TEST_ALERT_MS });
    notifier({ room: 'post:' + p.id, event: 'refresh' });
  }
  logEvent('test_alert', { tripId: trip.id, count: targets.length });
  return targets.length;
}

function postAction(postId, b) {
  const post = posts.get(postId);
  if (!post) throw httpError(404, 'Post is not registered.', 'POST_NOT_FOUND');
  const action = String(b.action || '');
  if (!['ack', 'clear_lane', 'escalate'].includes(action)) throw httpError(400, 'Invalid action.', 'BAD_ACTION');
  const trip = trips.get(String(b.tripId || ''));
  if (!trip) throw httpError(404, 'This alert is no longer active.', 'TRIP_NOT_FOUND');
  const ps = getPS(trip, postId);
  if (!ps.actions.some((a) => a.action === action)) {
    ps.actions.push({ action, at: now(), officer: clean(b.officer, 40) });
    logEvent('police_' + action, { tripId: trip.id, postId });
  }
  notifier({ room: 'trip:' + trip.id, event: 'refresh' });
  return { ok: true, actions: ps.actions };
}

function sweep() {
  const t = now();
  for (const [id, trip] of trips) {
    if (trip.active && t - trip.lastUpdate > CFG.TRIP_IDLE_END_MS) {
      trip.active = false; trip.status = 'stopped'; trip.endedAt = t;
      recordTripEnd(trip);
      logEvent('trip_idle_ended', { tripId: id });
    }
    if (!trip.active && t - (trip.endedAt || trip.lastUpdate) > CFG.TRIP_KEEP_MS) trips.delete(id);
  }
  for (const [pid, te] of tests) if (te.until < t) tests.delete(pid);
}

function stats() {
  return {
    posts: posts.size,
    activeTrips: [...trips.values()].filter((t) => t.active).length,
    events: events.slice(-30),
  };
}

module.exports = {
  CFG, httpError, clean, validPoint, setNotifier, setPersist, loadPosts, allPosts, deletePost,
  upsertPost, setOffDuty, startTrip, getTrip, updateLocation, stopTrip, replaceRoute,
  tripView, alertsForPost, testAlert, postAction, sweep, stats,
};
