'use strict';
// Run: node test-engine.js   (no internet / no npm install needed)
const assert = require('assert');
const { buildRoute } = require('./geo');
const E = require('./engine');
const R = require('./routing');

// 10 km straight road going east
const pts = [];
for (let i = 0; i <= 500; i++) pts.push({ lat: 25.0, lng: 85.0 + i * 0.0002 });
const route = buildRoute(pts);
const rd = { route, junctions: [], distance: route.total, duration: route.total / 10, fallback: false };

const p1 = E.upsertPost({ name: 'Mid Junction', lat: 25.0003, lng: 85.05, radius: 300 }); // on route
const p2 = E.upsertPost({ name: 'Far North', lat: 25.05, lng: 85.05, radius: 300 });       // not on route
const p3 = E.upsertPost({ name: 'Late Post', lat: 25.0, lng: 85.09, radius: 300 });        // on route, later

const trip = E.startTrip({ driverName: 'Ravi', ambulanceId: 'AMB-1', from: pts[0], to: pts[500], routeData: rd, destinationName: 'Hospital' });
const seen = [];
for (let lng = 85.0; lng <= 85.1; lng += 0.001) { // ~100 m steps
  E.updateLocation(trip.id, { lat: 25.0, lng, speed: 15 });
  const a1 = E.alertsForPost(p1.id).alerts[0];
  seen.push(a1 ? a1.status : 'none');
  assert.strictEqual(E.alertsForPost(p2.id).alerts.length, 0, 'off-route post must never be alerted');
}
const order = seen.filter((s, i) => i === 0 || s !== seen[i - 1]);
console.log('Post1 status sequence:', order.join(' -> '));
assert.deepStrictEqual(order.slice(0, 4), ['standby', 'approaching', 'imminent', 'passed']);
assert.ok(order.includes('passed'), 'must show passed');

// forward-only: after pass, going back must not re-alert
E.updateLocation(trip.id, { lat: 25.0, lng: 85.06, speed: 10 });
assert.ok(E.tripView(trip).chain > 5500, 'chain must not go backwards');

// ack action reaches driver
const t2 = E.startTrip({ driverName: 'Ravi', ambulanceId: 'AMB-2', from: pts[0], to: pts[500], routeData: rd });
E.updateLocation(t2.id, { lat: 25.0, lng: 85.044, speed: 12 });
const al = E.alertsForPost(p1.id).alerts.find((a) => a.tripId === t2.id);
assert.ok(al && (al.status === 'approaching' || al.status === 'imminent'), 'alert for new trip');
E.postAction(p1.id, { tripId: t2.id, action: 'ack', officer: 'SI Kumar' });
assert.ok(E.tripView(t2).actions.some((a) => a.action === 'ack'), 'driver sees ack');
assert.ok(E.alertsForPost(p1.id).alerts.find((a) => a.tripId === t2.id).acked, 'alert marked acked');

// stale GPS pauses automation
t2.lastUpdate -= 60000;
assert.strictEqual(E.alertsForPost(p1.id).alerts.find((a) => a.tripId === t2.id).status, 'paused');
t2.lastUpdate += 60000;

// off-route detection (3 bad fixes)
for (let i = 0; i < 3; i++) E.updateLocation(t2.id, { lat: 25.02, lng: 85.045, speed: 12 });
assert.strictEqual(E.tripView(t2).status, 'off_route');
E.updateLocation(t2.id, { lat: 25.0, lng: 85.046, speed: 12 });
assert.strictEqual(E.tripView(t2).status, 'ok', 'recovers when back on route');

// test alert
const n = E.testAlert(t2);
assert.ok(n >= 1);
assert.ok(E.alertsForPost(p3.id).alerts.some((a) => a.status === 'test') || E.alertsForPost(p1.id).alerts.some((a) => a.status === 'test'));

// completion
E.stopTrip(trip.id);
assert.strictEqual(E.tripView(trip).status, 'stopped');

// fallback route works without internet
const fb = R.fallbackRoute({ lat: 25.0, lng: 85.0 }, { lat: 25.03, lng: 85.03 });
assert.ok(fb.fallback && fb.route.points.length > 10 && fb.junctions.length > 3);

// errors
assert.throws(() => E.updateLocation('nope', { lat: 1, lng: 1 }), (e) => e.code === 'TRIP_NOT_FOUND');
assert.throws(() => E.upsertPost({ lat: 'x', lng: 1 }), (e) => e.status === 400);
console.log('ALL ENGINE TESTS PASSED');
