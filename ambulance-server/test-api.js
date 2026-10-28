'use strict';
// Run: node test-api.js   (starts the real server on a test port, works offline)
const assert = require('assert');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const PORT = 3999;
const BASE = 'http://127.0.0.1:' + PORT;
const file = path.join(os.tmpdir(), 'amburoute-api-' + Date.now() + '.json');
const env = { ...process.env, PORT: String(PORT), ADMIN_CODE: 'secret123', DATA_FILE: file, MONGODB_URI: '', OSRM_URL: 'http://127.0.0.1:9', NOMINATIM_URL: 'http://127.0.0.1:9', REQUIRE_REGISTERED_AMBULANCE: 'true' };

function start() {
  const p = spawn('node', ['server.js'], { env, stdio: ['ignore', 'pipe', 'pipe'] });
  return new Promise((resolve, reject) => {
    p.stdout.on('data', (d) => { if (String(d).includes('running on port')) resolve(p); });
    p.on('exit', (c) => reject(new Error('server exited ' + c)));
    setTimeout(() => reject(new Error('server start timeout')), 8000);
  });
}
const call = async (method, p, body, headers = {}) => {
  const r = await fetch(BASE + p, { method, headers: { 'Content-Type': 'application/json', ...headers }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => ({})) };
};
const admin = { 'x-admin-code': 'secret123' };

(async () => {
  let srv = await start();
  try {
    assert.strictEqual((await call('GET', '/health')).body.ok, true);
    assert.strictEqual((await call('GET', '/api/admin/summary')).status, 401, 'admin needs the code');
    assert.strictEqual((await call('GET', '/api/admin/summary', null, { 'x-admin-code': 'wrong' })).status, 401);
    assert.strictEqual((await call('GET', '/api/admin/summary', null, admin)).body.database, 'file');
    const page = await fetch(BASE + '/admin');
    assert.strictEqual(page.status, 200, 'admin page must load');

    // admin adds a place -> driver search finds it
    const add = await call('POST', '/api/admin/places', { name: 'Sadar Hospital', category: 'hospital', lat: 25.2, lng: 85.52, aliases: 'sadar aspatal' }, admin);
    assert.ok(add.body.ok && add.body.place.id);
    const s = await call('GET', '/api/geocode?q=sadar%20aspatal');
    assert.strictEqual(s.body.results[0].name, 'Sadar Hospital', 'local place must be found even when the map service is down');

    // app user saves a place from the phone
    const fromApp = await call('POST', '/api/places', { name: 'Gandhi Maidan Bihar Sharif', category: 'landmark', lat: 25.197, lng: 85.516 });
    assert.ok(fromApp.body.ok);
    assert.strictEqual((await call('POST', '/api/places', { name: 'Gandhi Maidan Bihar Sharif', category: 'landmark', lat: 25.197, lng: 85.516 })).body.duplicate, true);

    const near = await call('GET', '/api/places/nearby?category=hospital&lat=25.2&lng=85.52');
    assert.ok(near.body.results.some((p) => p.name === 'Sadar Hospital'));

    // only registered ambulances may start a trip
    const bad = await call('POST', '/api/trips/start', { ambulanceId: 'AMB-999', from: { lat: 25.2, lng: 85.5 }, to: { lat: 25.21, lng: 85.53 } });
    assert.strictEqual(bad.status, 403);
    await call('POST', '/api/admin/ambulances', { id: 'amb-101', driverName: 'Ravi' }, admin);
    const ok = await call('POST', '/api/trips/start', { ambulanceId: 'amb-101', driverName: 'Ravi', from: { lat: 25.2, lng: 85.5 }, to: { lat: 25.21, lng: 85.53 }, destinationName: 'Sadar Hospital' });
    assert.strictEqual(ok.status, 200, JSON.stringify(ok.body));
    await call('POST', '/api/posts/register', { name: 'Test Chowk', lat: 25.205, lng: 85.515, radius: 800 });
    // IoT telemetry endpoint
    const telRes = await call('POST', '/api/iot/AMB-101/telemetry', { lat: 25.201, lng: 85.51, speed: 48, sats: 8, fix: true });
    assert.strictEqual(telRes.status, 200);
    assert.strictEqual(telRes.body.telemetry.sats, 8);

    // Pre Bed Booked & Gate Inspection endpoints
    const bedPost = await call('POST', `/api/trips/${ok.body.tripId}/bed-booking`, {
      hospitalName: 'Sadar Hospital',
      bedType: 'ICU Bed + Ventilator',
      patientBrief: 'Accident trauma patient, oxygen support required',
      contactPhone: '9876543210'
    });
    assert.strictEqual(bedPost.status, 200);
    assert.strictEqual(bedPost.body.booking.status, 'CONFIRMED');

    const bedGet = await call('GET', `/api/trips/${ok.body.tripId}/bed-booking`);
    assert.strictEqual(bedGet.status, 200);
    assert.strictEqual(bedGet.body.booking.bedType, 'ICU Bed + Ventilator');

    const gatePost = await call('POST', '/api/gate-inspection', {
      ambulanceId: 'AMB-101',
      driverName: 'Ravi',
      checklist: { oxygen: true, fuel: true, siren: true }
    });
    assert.strictEqual(gatePost.status, 200);
    assert.strictEqual(gatePost.body.report.status, 'APPROVED_ON_GATE');

    const hosp = await call('GET', '/api/hospitals/directory');
    assert.strictEqual(hosp.status, 200);
    assert.ok(hosp.body.hospitals.length > 0);

    await call('POST', `/api/trips/${ok.body.tripId}/stop`, {});

    // restart -> everything must still be there
    await new Promise((r) => setTimeout(r, 500));
    srv.removeAllListeners('exit'); srv.kill('SIGTERM');
    await new Promise((r) => setTimeout(r, 400));
    srv = await start();
    assert.strictEqual((await call('GET', '/api/geocode?q=sadar%20hospital')).body.results[0].name, 'Sadar Hospital', 'places survive restart');
    const posts = await call('GET', '/api/admin/posts', null, admin);
    assert.ok(posts.body.posts.some((p) => p.name === 'Test Chowk' && p.online === false), 'police post survives restart and is offline until phone reconnects');
    assert.strictEqual((await call('GET', '/api/admin/ambulances', null, admin)).body.ambulances[0].id, 'AMB-101');
    const trips = await call('GET', '/api/admin/trips', null, admin);
    assert.strictEqual(trips.body.trips.length, 1, 'finished trip is saved in history');
    console.log('ALL API TESTS PASSED');
  } finally {
    srv.removeAllListeners('exit'); srv.kill('SIGTERM');
    setTimeout(() => { fs.rmSync(file, { force: true }); process.exit(process.exitCode || 0); }, 400);
  }
})().catch((e) => { console.error('FAILED:', e); process.exitCode = 1; });
