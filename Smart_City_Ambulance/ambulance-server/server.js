'use strict';
const express = require('express');
const http = require('http');
const cors = require('cors');
const { Server } = require('socket.io');
const path = require('path');
const engine = require('./engine');
const routing = require('./routing');
const { Store } = require('./db');
const places = require('./places');
const iot = require('./iot');

const store = new Store();

const app = express();
app.use(cors());
app.use(express.json({ limit: '200kb' }));

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' }, transports: ['websocket', 'polling'] });
io.on('connection', (socket) => {
  socket.on('join_post', (id) => { if (typeof id === 'string') socket.join('post:' + id); });
  socket.on('join_trip', (id) => { if (typeof id === 'string') socket.join('trip:' + id); });
});
engine.setNotifier(({ room, event }) => io.to(room).emit(event, { t: Date.now() }));
engine.setIotHook((ev) => iot.onEngineEvent(ev)); // alerts switch the IoT display + buzzer of the police post automatically

// ---- optional access codes (set DRIVER_CODE / POLICE_CODE in Render env to enable) ----
const DRIVER_CODE = process.env.DRIVER_CODE || '';
const POLICE_CODE = process.env.POLICE_CODE || '';
const ADMIN_CODE = process.env.ADMIN_CODE || '';
const REQUIRE_REGISTERED = ['1', 'true', 'yes'].includes(String(process.env.REQUIRE_REGISTERED_AMBULANCE || '').toLowerCase());

// very small rate limiter (per IP, per minute) to stop spam
const hits = new Map();
function limit(max) {
  return (req, res, next) => {
    const key = req.ip + '|' + req.path;
    const t = Date.now();
    const h = (hits.get(key) || []).filter((x) => t - x < 60000);
    if (h.length >= max) return res.status(429).json({ error: 'Too many requests. Please wait a minute.', code: 'RATE_LIMIT' });
    h.push(t);
    hits.set(key, h);
    next();
  };
}
setInterval(() => hits.clear(), 10 * 60 * 1000).unref();

function adminGuard(req, res, next) {
  if (!ADMIN_CODE) return res.status(403).json({ error: 'Admin is switched off. Set ADMIN_CODE in the server settings first.', code: 'ADMIN_OFF' });
  if (String(req.get('x-admin-code') || '') !== ADMIN_CODE) return res.status(401).json({ error: 'Wrong admin code.', code: 'BAD_ADMIN_CODE' });
  next();
}
function guard(role) {
  return (req, res, next) => {
    const sent = String(req.get('x-access-code') || '');
    let allowed;
    if (role === 'driver') allowed = DRIVER_CODE ? [DRIVER_CODE] : null;
    else if (role === 'police') allowed = POLICE_CODE ? [POLICE_CODE] : null;
    else allowed = DRIVER_CODE || POLICE_CODE ? [DRIVER_CODE, POLICE_CODE].filter(Boolean) : null;
    if (!allowed || allowed.includes(sent)) return next();
    return res.status(401).json({ error: 'Incorrect access code.', code: 'BAD_CODE' });
  };
}
const wrap = (fn) => (req, res) =>
  Promise.resolve(fn(req, res)).catch((err) => {
    const status = err.status || 500;
    if (status >= 500) console.error(err);
    res.status(status).json({ error: status >= 500 ? 'Something went wrong on the server. Please try again.' : err.message, code: err.code || 'ERROR' });
  });

const parsePoint = (o) => {
  if (!o) return null;
  const lat = Number(o.lat), lng = Number(o.lng);
  return engine.validPoint(lat, lng) ? { lat, lng } : null;
};
const r6 = (n) => Math.round(n * 1e6) / 1e6;
const routePayload = (rd) => ({
  points: rd.route.points.map((p) => [r6(p.lat), r6(p.lng)]),
  junctions: rd.junctions.map((j) => ({ id: j.id, name: j.name, lat: r6(j.lat), lng: r6(j.lng), chain: j.chain })),
  distance: Math.round(rd.distance),
  duration: Math.round(rd.duration),
  fallback: !!rd.fallback,
});

// ---- public ----
app.get('/', (req, res) => res.json({ name: 'AmbuRoute Alert AI server', ok: true }));
app.get('/health', (req, res) => res.json({ ok: true, time: Date.now() }));
app.get('/api/status', guard('any'), (req, res) => res.json({
  ok: true, ...engine.stats(),
  database: store.kind, databaseWarning: store.warning,
  places: store.count('places'), ambulances: store.count('ambulances'),
}));
app.get('/admin', (req, res) => res.sendFile(path.join(__dirname, 'public', 'admin.html')));

// ---- search + route ----
// 1) our own local places database (fast, knows local names)  2) free map search (only if needed)
app.get('/api/geocode', guard('any'), limit(60), wrap(async (req, res) => {
  const q = String(req.query.q || '').trim().slice(0, 120);
  if (q.length < 2) return res.json({ ok: true, results: [] });
  const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
  const local = places.search(q, near, 8);
  let results = local;
  let note = '';
  if (local.length < 4) {
    try {
      const web = await routing.geocode(q, near);
      const seen = new Set(local.map((p) => p.name.toLowerCase()));
      results = local.concat(web.filter((w) => !seen.has(w.name.toLowerCase())).map((w) => ({ ...w, local: false, category: 'other' })));
    } catch (e) {
      console.warn('geocode failed:', e.message);
      if (!local.length) {
        return res.status(502).json({ error: 'Place search is busy right now. Please try again, or tap on the map to choose a place.', code: 'GEOCODE_FAIL' });
      }
      note = 'Showing saved places only.';
    }
  }
  res.json({ ok: true, results, note });
}));

app.get('/api/places/nearby', guard('any'), limit(60), wrap(async (req, res) => {
  const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
  res.json({ ok: true, results: places.nearby(String(req.query.category || 'hospital'), near, 10) });
}));

// Drivers and police can save a new local place from the app (it is marked "app" so the admin can check it)
app.post('/api/places', guard('any'), limit(20), wrap(async (req, res) => {
  const b = req.body || {};
  const dup = places.all().find((p) => p.name.toLowerCase() === String(b.name || '').trim().toLowerCase() && Math.abs(p.lat - Number(b.lat)) < 0.002 && Math.abs(p.lng - Number(b.lng)) < 0.002);
  if (dup) return res.json({ ok: true, place: dup, duplicate: true });
  const p = places.save({ name: b.name, category: b.category, area: b.area, lat: b.lat, lng: b.lng, aliases: b.aliases }, 'app');
  res.json({ ok: true, place: p });
}));

app.post('/api/route', guard('driver'), wrap(async (req, res) => {
  const from = parsePoint(req.body.from), to = parsePoint(req.body.to);
  if (!from || !to) throw engine.httpError(400, 'Invalid start / destination.', 'BAD_POINTS');
  res.json({ ok: true, route: routePayload(await routing.getRoute(from, to)) });
}));

// ---- driver trips ----
app.post('/api/trips/start', guard('driver'), wrap(async (req, res) => {
  const b = req.body || {};
  const from = parsePoint(b.from), to = parsePoint(b.to);
  if (!from || !to) throw engine.httpError(400, 'Invalid start / destination.', 'BAD_POINTS');
  const ambId = (engine.clean(b.ambulanceId, 20) || 'AMB').toUpperCase();
  if (REQUIRE_REGISTERED) {
    const a = store.get('ambulances', ambId);
    if (!a || a.active === false) throw engine.httpError(403, 'This ambulance number is not registered. Please contact the admin.', 'AMBULANCE_NOT_REGISTERED');
  }
  const rd = await routing.getRoute(from, to);
  const trip = engine.startTrip({
    driverName: engine.clean(b.driverName, 40) || 'Driver',
    ambulanceId: ambId,
    destinationName: engine.clean(b.destinationName, 120),
    from, to, routeData: rd,
  });
  res.json({ ok: true, tripId: trip.id, route: routePayload(rd), state: engine.tripView(trip) });
}));

app.post('/api/trips/:id/location', guard('driver'), wrap(async (req, res) => {
  res.json(engine.updateLocation(req.params.id, req.body || {}));
}));

app.get('/api/trips/:id', guard('driver'), wrap(async (req, res) => {
  res.json(engine.tripView(engine.getTrip(req.params.id)));
}));

app.post('/api/trips/:id/reroute', guard('driver'), wrap(async (req, res) => {
  const trip = engine.getTrip(req.params.id);
  const from = parsePoint(req.body);
  if (!from) throw engine.httpError(400, 'Invalid GPS location.', 'BAD_LOCATION');
  const rd = await routing.getRoute(from, trip.to);
  engine.replaceRoute(trip, rd, from);
  res.json({ ok: true, route: routePayload(rd), state: engine.tripView(trip) });
}));

app.post('/api/trips/:id/test-alert', guard('driver'), wrap(async (req, res) => {
  const trip = engine.getTrip(req.params.id);
  res.json({ ok: true, count: engine.testAlert(trip) });
}));

app.post('/api/trips/:id/stop', guard('driver'), wrap(async (req, res) => {
  engine.stopTrip(req.params.id);
  res.json({ ok: true });
}));

// ---- police posts ----
app.post('/api/posts/register', guard('police'), wrap(async (req, res) => {
  const post = engine.upsertPost(req.body || {});
  res.json({ ok: true, post });
}));

app.get('/api/posts/:id/alerts', guard('police'), wrap(async (req, res) => {
  res.json(engine.alertsForPost(req.params.id));
}));

app.post('/api/posts/:id/action', guard('police'), wrap(async (req, res) => {
  res.json(engine.postAction(req.params.id, req.body || {}));
}));

app.post('/api/posts/:id/offduty', guard('police'), wrap(async (req, res) => {
  engine.setOffDuty(req.params.id);
  res.json({ ok: true });
}));

// ---- driver extras: priority + quick message to police ----
app.post('/api/trips/:id/priority', guard('driver'), wrap(async (req, res) => {
  res.json({ ok: true, priority: engine.setPriority(req.params.id, String((req.body || {}).priority || '')) });
}));
app.post('/api/trips/:id/message', guard('driver'), wrap(async (req, res) => {
  res.json({ ok: true, message: engine.setMessage(req.params.id, String((req.body || {}).text || '')) });
}));

// ---- police posts that are online (driver map shows them all, not only the ones on the route) ----
app.get('/api/posts/online', guard('any'), limit(60), (req, res) => res.json({ ok: true, posts: engine.onlinePosts() }));

// ---- IoT devices (ESP32 etc.): display + buzzer ----
// device id = police post id (post device) or ambulance number (ambulance device)
app.get('/api/iot/:id/state', guard('any'), limit(400), (req, res) => {
  const st = iot.deviceState(req.params.id);
  if (!st) return res.status(400).json({ error: 'Invalid device ID.', code: 'BAD_DEVICE' });
  res.json(st);
});
app.get('/api/iot/:id', guard('any'), limit(120), (req, res) => res.json({ ok: true, device: iot.getView(req.params.id) }));
app.post('/api/iot/:id/command', guard('any'), limit(60), wrap(async (req, res) => {
  const b = req.body || {};
  res.json({ ok: true, device: iot.command(req.params.id, b, cleanTxt(b.by, 40)) });
}));
// driver -> all police devices that are on the ambulance route
app.post('/api/trips/:id/iot', guard('driver'), limit(60), wrap(async (req, res) => {
  const trip = engine.getTrip(req.params.id);
  const b = req.body || {};
  const ids = engine.routePostIds(trip);
  const cmd = {};
  if ('display' in b) cmd.display = b.display;
  if ('buzzer' in b) cmd.buzzer = b.buzzer;
  for (const id of ids) iot.command(id, cmd, 'Driver ' + cleanTxt(trip.ambulanceId, 20));
  res.json({ ok: true, count: ids.length });
}));
app.get('/api/admin/iot', adminGuard, (req, res) => res.json({ ok: true, devices: iot.listDevices() }));

// ---- admin (data entry) ----
const cleanTxt = (v, n) => engine.clean(typeof v === 'string' ? v : '', n);
app.get('/api/admin/summary', adminGuard, (req, res) => res.json({
  ok: true, database: store.kind, warning: store.warning,
  places: store.count('places'), posts: engine.allPosts().length, ambulances: store.count('ambulances'), trips: store.count('trips'),
  categories: places.CATEGORIES,
}));
app.get('/api/admin/places', adminGuard, (req, res) => {
  const q = String(req.query.q || '').trim();
  const list = q ? places.search(q, null, 100).map((r) => store.get('places', r.id)).filter(Boolean) : places.all();
  res.json({ ok: true, places: list.sort((a, b) => a.name.localeCompare(b.name)).slice(0, 500) });
});
app.post('/api/admin/places', adminGuard, wrap(async (req, res) => res.json({ ok: true, place: places.save(req.body || {}, 'admin') })));
app.delete('/api/admin/places/:id', adminGuard, (req, res) => res.json({ ok: places.remove(req.params.id) }));
app.post('/api/admin/places/import', adminGuard, wrap(async (req, res) => res.json({ ok: true, ...places.importCsv(String((req.body || {}).csv || '')) })));

app.get('/api/admin/posts', adminGuard, (req, res) => {
  const t = Date.now();
  res.json({ ok: true, posts: engine.allPosts().map((p) => ({ ...p, online: p.onDuty && t - p.lastSeen < engine.CFG.POST_STALE_MS })) });
});
app.post('/api/admin/posts', adminGuard, wrap(async (req, res) => {
  const b = req.body || {};
  const post = engine.upsertPost({ id: b.id, name: b.name, area: b.area, officer: b.officer, lat: b.lat, lng: b.lng, radius: b.radius });
  post.lastSeen = 0; // stays offline until a police phone connects
  res.json({ ok: true, post });
}));
app.delete('/api/admin/posts/:id', adminGuard, (req, res) => {
  const ok = engine.deletePost(req.params.id);
  store.remove('posts', req.params.id);
  res.json({ ok });
});

app.get('/api/admin/ambulances', adminGuard, (req, res) => res.json({ ok: true, ambulances: store.list('ambulances'), required: REQUIRE_REGISTERED }));
app.post('/api/admin/ambulances', adminGuard, wrap(async (req, res) => {
  const b = req.body || {};
  const id = cleanTxt(b.id, 20).toUpperCase().replace(/\s+/g, '-');
  if (id.length < 2) throw engine.httpError(400, 'Ambulance number is too short.', 'BAD_ID');
  const old = store.get('ambulances', id);
  const a = {
    id, driverName: cleanTxt(b.driverName, 40), phone: cleanTxt(b.phone, 20), hospital: cleanTxt(b.hospital, 80),
    active: b.active !== false && b.active !== 'false', createdAt: old ? old.createdAt : Date.now(),
  };
  store.put('ambulances', a);
  res.json({ ok: true, ambulance: a });
}));
app.delete('/api/admin/ambulances/:id', adminGuard, (req, res) => res.json({ ok: store.remove('ambulances', req.params.id) }));

app.get('/api/admin/trips', adminGuard, (req, res) => {
  res.json({ ok: true, trips: store.list('trips').sort((a, b) => b.startedAt - a.startedAt).slice(0, 100) });
});

// ---- errors ----
app.use((req, res) => res.status(404).json({ error: 'Endpoint not found.', code: 'NOT_FOUND' }));
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  res.status(err.status || 400).json({ error: 'Invalid request.', code: 'BAD_REQUEST' });
});
process.on('unhandledRejection', (e) => console.error('unhandledRejection', e));
process.on('uncaughtException', (e) => console.error('uncaughtException', e));

setInterval(engine.sweep, 30000).unref();
const PORT = process.env.PORT || 3000;

(async () => {
  await store.init();
  places.init(store);
  engine.loadPosts(store.list('posts'));
  engine.setPersist({
    post: (p) => store.put('posts', { id: p.id, name: p.name, area: p.area, officer: p.officer, lat: p.lat, lng: p.lng, radius: p.radius, onDuty: p.onDuty, registeredAt: p.registeredAt }),
    tripEnd: (t) => { store.put('trips', t); const all = store.list('trips'); if (all.length > 1000) all.sort((a, b) => a.startedAt - b.startedAt).slice(0, all.length - 1000).forEach((x) => store.remove('trips', x.id)); },
  });
  console.log(`Database: ${store.kind} | places: ${store.count('places')} | police posts: ${engine.allPosts().length}`);
  if (store.warning) console.warn('WARNING: ' + store.warning);
  server.listen(PORT, '0.0.0.0', () => console.log('AmbuRoute server running on port ' + PORT));
})();

const bye = () => { store.flush(); process.exit(0); };
process.on('SIGTERM', bye);
process.on('SIGINT', bye);
