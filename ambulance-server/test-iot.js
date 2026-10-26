'use strict';
// Run: node test-iot.js   (no internet / no npm install needed)
const assert = require('assert');
const { buildRoute } = require('./geo');
const E = require('./engine');
const IOT = require('./iot');

E.setIotHook((ev) => IOT.onEngineEvent(ev));

const pts = [];
for (let i = 0; i <= 500; i++) pts.push({ lat: 25.0, lng: 85.0 + i * 0.0002 });
const route = buildRoute(pts);
const rd = { route, junctions: [], distance: route.total, duration: route.total / 10, fallback: false };

const post = E.upsertPost({ name: 'Mid Junction', lat: 25.0003, lng: 85.05, radius: 300 });
const trip = E.startTrip({ driverName: 'Ravi', ambulanceId: 'AMB-7', from: pts[0], to: pts[500], routeData: rd, destinationName: 'Hospital' });

// 1) manual command: display + buzzer
let v = IOT.command('POST-A', { display: { text: 'HELLO\nWORLD', seconds: 30 }, buzzer: { pattern: 'beep', seconds: 5 } }, 'SI Kumar');
assert.ok(v.display.on && v.buzzer.on && v.display.text === 'HELLO\nWORLD');
let st = IOT.deviceState('POST-A');
assert.ok(st.display.on && st.buzzer.pattern === 'beep');
assert.ok(IOT.getView('POST-A').online, 'device that polled is online');
v = IOT.command('POST-A', { buzzer: { pattern: 'off' } });
assert.ok(!v.buzzer.on, 'buzzer switched off');
assert.ok(v.display.on, 'display untouched');
// buzzer is limited to 60 s
v = IOT.command('POST-A', { buzzer: { pattern: 'continuous', seconds: 9999 } });
assert.ok(v.buzzer.remainingSec <= 60, 'buzzer fail-safe limit');
assert.throws(() => IOT.command('x', {}), (e) => e.code === 'BAD_DEVICE');

// 2) auto mode: engine alert switches the device of the post
IOT.command(post.id, { auto: true });
IOT.command(post.id, { display: null, buzzer: { pattern: 'off' } });
IOT.getView(post.id);
// manual command just sent => auto is on hold, so wait it out
const dev = IOT.deviceState(post.id); // creates / touches
assert.ok(dev.ok);
// make the manual hold expire (test only): re-create state
IOT.reset();
IOT.deviceState(post.id);
E.updateLocation(trip.id, { lat: 25.0, lng: 85.043, speed: 15 }); // ~700 m before the post => approaching
let s1 = IOT.getView(post.id);
assert.ok(s1.display.on && /AMBULANCE/.test(s1.display.text) && s1.buzzer.pattern === 'beep', 'approaching -> display + beep');
E.updateLocation(trip.id, { lat: 25.0, lng: 85.048, speed: 15 }); // ~200 m => imminent
s1 = IOT.getView(post.id);
assert.strictEqual(s1.buzzer.pattern, 'siren', 'imminent -> siren');
E.setPriority(trip.id, 'critical');
E.updateLocation(trip.id, { lat: 25.0, lng: 85.0485, speed: 15 });
assert.ok(/CRITICAL/.test(IOT.getView(post.id).display.text), 'critical priority shows on the display');
E.updateLocation(trip.id, { lat: 25.0, lng: 85.052, speed: 15 }); // passed
s1 = IOT.getView(post.id);
assert.ok(!s1.display.on && !s1.buzzer.on, 'passed -> everything off');

// 3) manual command holds auto for a while
const trip2 = E.startTrip({ driverName: 'R', ambulanceId: 'AMB-8', from: pts[0], to: pts[500], routeData: rd });
IOT.command(post.id, { display: { text: 'KEEP ME', seconds: 60 } }, 'Officer');
E.updateLocation(trip2.id, { lat: 25.0, lng: 85.043, speed: 15 });
assert.strictEqual(IOT.getView(post.id).display.text, 'KEEP ME', 'manual command is not overwritten by auto');

// 4) auto can be switched off
IOT.command(post.id, { auto: false, display: null });
E.updateLocation(trip2.id, { lat: 25.0, lng: 85.047, speed: 15 });
assert.ok(!IOT.getView(post.id).display.on, 'auto off -> device stays quiet');

// 5) live ambulances + online posts + quick message
const live = E.alertsForPost(post.id).ambulances;
assert.ok(live.length >= 1 && live[0].ambulanceId && live[0].distToPost >= 0, 'police sees live ambulances');
assert.ok(E.onlinePosts().some((p) => p.id === post.id), 'driver sees online posts');
E.setMessage(trip2.id, 'Patient critical <b>');
const al = E.alertsForPost(post.id).alerts.find((a) => a.tripId === trip2.id);
assert.ok(al && al.message && al.message.text === 'Patient critical b', 'message reaches police alert');
assert.ok(E.routePostIds(trip2).includes(post.id), 'post is on the route');

console.log('ALL IOT TESTS PASSED');
