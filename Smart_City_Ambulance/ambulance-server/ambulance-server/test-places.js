'use strict';
// Run: node test-places.js   (works offline)
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store } = require('./db');
const places = require('./places');

(async () => {
  const file = path.join(os.tmpdir(), 'amburoute-test-' + Date.now() + '.json');
  let store = await new Store().init({ mongoUri: '', file });
  places.init(store);
  assert.ok(store.count('places') >= 1, 'starter places should be loaded');

  places.save({ name: 'Sadar Hospital', category: 'hospital', lat: 25.2, lng: 85.52, area: 'Station Road', aliases: 'sadar aspatal, civil hospital' }, 'admin');
  places.save({ name: 'Shri Krishna Chowk', category: 'market', lat: 25.198, lng: 85.51, aliases: ['krishna chauraha'] }, 'admin');
  places.save({ name: 'Bihar Sharif Railway Station', category: 'transport', lat: 25.21, lng: 85.53 }, 'admin');

  const top = (q) => (places.search(q, null)[0] || {}).name;
  assert.strictEqual(top('sadar hospital'), 'Sadar Hospital');
  assert.strictEqual(top('sadar'), 'Sadar Hospital');
  assert.strictEqual(top('sadar aspatal'), 'Sadar Hospital', 'alias must work');
  assert.strictEqual(top('sadr hospitl'), 'Sadar Hospital', 'spelling mistakes must work');
  assert.strictEqual(top('krishna chauraha'), 'Shri Krishna Chowk', 'alias must work');
  assert.strictEqual(top('biharsharif railway'), 'Bihar Sharif Railway Station', 'no-space spelling must work');
  assert.strictEqual(places.search('zzzzqq', null).length, 0, 'nonsense must give nothing');

  const near = places.nearby('hospital', { lat: 25.2, lng: 85.52 }, 5);
  assert.ok(near.length >= 2 && near[0].category === 'hospital');
  assert.ok(near[0].distance <= near[near.length - 1].distance, 'nearest first');

  assert.throws(() => places.save({ name: 'X', lat: 25, lng: 85 }), /too short/);
  assert.throws(() => places.save({ name: 'Bad place', lat: 'abc', lng: 85 }), /latitude/);

  const imp = places.importCsv('name,category,lat,lng\nCity Mall,market,25.19,85.51,Main Road,,mall\nBroken Line,market,x,y');
  assert.strictEqual(imp.added, 1);
  assert.strictEqual(imp.errors.length, 1);

  // deleted starter places must not come back after a restart
  places.remove('seed-rajgir');
  store.flush();
  await new Promise((r) => setTimeout(r, 50));
  store = await new Store().init({ mongoUri: '', file });
  places.init(store);
  assert.ok(!store.get('places', 'seed-rajgir'), 'deleted seed place must stay deleted');
  assert.strictEqual((places.search('sadar hospital', null)[0] || {}).name, 'Sadar Hospital', 'data must survive restart');

  fs.rmSync(file, { force: true });
  console.log('ALL PLACES + DATABASE TESTS PASSED');
})().catch((e) => { console.error('FAILED:', e); process.exit(1); });
