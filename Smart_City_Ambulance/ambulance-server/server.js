'use strict';
const express = require('express');
const http = require('http');
const cors = require('cors');
const { Server } = require('socket.io');
const engine = require('./engine');
const routing = require('./routing');

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

// ---- optional access codes (set DRIVER_CODE / POLICE_CODE in Render env to enable) ----
const DRIVER_CODE = process.env.DRIVER_CODE || '';
const POLICE_CODE = process.env.POLICE_CODE || '';
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
app.get('/api/status', guard('any'), (req, res) => res.json({ ok: true, ...engine.stats() }));

// ---- search + route ----
app.get('/api/geocode', guard('any'), wrap(async (req, res) => {
  const q = String(req.query.q || '').trim().slice(0, 120);
  if (q.length < 2) return res.json({ ok: true, results: [] });
  const near = parsePoint({ lat: req.query.lat, lng: req.query.lng });
  try {
    res.json({ ok: true, results: await routing.geocode(q, near) });
  } catch (e) {
    console.warn('geocode failed:', e.message);
    res.status(502).json({ error: 'The search service is busy right now. Please try again shortly or tap on the map to choose a place.', code: 'GEOCODE_FAIL' });
  }
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
  const rd = await routing.getRoute(from, to);
  const trip = engine.startTrip({
    driverName: engine.clean(b.driverName, 40) || 'Driver',
    ambulanceId: engine.clean(b.ambulanceId, 20) || 'AMB',
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

// ---- errors ----
app.use((req, res) => res.status(404).json({ error: 'Endpoint not found.', code: 'NOT_FOUND' }));
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  res.status(err.status || 400).json({ error: 'Invalid request.', code: 'BAD_REQUEST' });
});
process.on('unhandledRejection', (e) => console.error('unhandledRejection', e));
process.on('uncaughtException', (e) => console.error('uncaughtException', e));

setInterval(engine.sweep, 30000).unref();
const PORT = process.env.PORT || 3000;
server.listen(PORT, '0.0.0.0', () => console.log('AmbuRoute server running on port ' + PORT));
