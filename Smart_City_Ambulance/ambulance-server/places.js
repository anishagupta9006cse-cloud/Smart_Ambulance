'use strict';
// Local places database: hospitals, police stations, chowks, markets, landmarks...
// The search understands small spelling mistakes (example: "biharsarif", "sadar hospitl").
const fs = require('fs');
const path = require('path');
const { haversine } = require('./geo');

const CATEGORIES = ['hospital', 'police', 'transport', 'market', 'religious', 'education', 'landmark', 'area'];
let store = null;

const clean = (v, n) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f<>]/g, '').trim().slice(0, n) : '');
const validPoint = (lat, lng) => Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
const rid = () => 'L' + Date.now().toString(36).toUpperCase() + Math.random().toString(36).slice(2, 5).toUpperCase();

// "Bihar-Sharif Chowk" -> "bihar sharif chowk"
function norm(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[^a-z0-9\u0900-\u097f ]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
const squash = (s) => norm(s).replace(/ /g, '');

function editDistance(a, b, max) {
  if (Math.abs(a.length - b.length) > max) return max + 1;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}

function toPlace(b, old) {
  const lat = Number(b.lat), lng = Number(b.lng);
  if (!validPoint(lat, lng)) {
    const e = new Error('Please give a correct latitude and longitude.');
    e.status = 400; e.code = 'BAD_POINT';
    throw e;
  }
  const name = clean(b.name, 90);
  if (name.length < 2) {
    const e = new Error('Place name is too short.');
    e.status = 400; e.code = 'BAD_NAME';
    throw e;
  }
  const category = CATEGORIES.includes(b.category) ? b.category : 'landmark';
  let aliases = b.aliases;
  if (typeof aliases === 'string') aliases = aliases.split(/[,;|]/);
  aliases = Array.isArray(aliases) ? aliases.map((a) => clean(String(a), 60)).filter(Boolean).slice(0, 12) : [];
  return {
    id: old ? old.id : (typeof b.id === 'string' && /^[A-Za-z0-9_-]{3,50}$/.test(b.id) ? b.id : rid()),
    name,
    category,
    area: clean(b.area, 90),
    phone: clean(b.phone, 20),
    aliases,
    lat: Math.round(lat * 1e6) / 1e6,
    lng: Math.round(lng * 1e6) / 1e6,
    approx: b.approx === true || b.approx === 'true',
    source: old ? old.source : clean(b.source, 12) || 'admin',
    createdAt: old ? old.createdAt : Date.now(),
    updatedAt: Date.now(),
  };
}

function init(s) {
  store = s;
  // First start only: add the starter places. Deleted places never come back.
  if (!store.get('meta', 'seeded')) {
    try {
      const seed = JSON.parse(fs.readFileSync(path.join(__dirname, 'data', 'places.seed.json'), 'utf8'));
      for (const p of seed) if (!store.get('places', p.id)) store.put('places', { ...toPlace({ ...p, source: 'seed' }), id: p.id, source: 'seed' });
    } catch (e) {
      console.warn('seed places could not be loaded:', e.message);
    }
    store.put('meta', { id: 'seeded', at: Date.now() });
  }
}

const all = () => store.list('places');
const publicView = (p, near) => ({
  id: p.id,
  name: p.name,
  category: p.category,
  area: p.area || '',
  phone: p.phone || '',
  lat: p.lat,
  lng: p.lng,
  local: true,
  distance: near ? Math.round(haversine(near, p)) : undefined,
});

// Returns the best matches first.
function search(q, near, limit = 8) {
  const qn = norm(q);
  if (qn.length < 2) return [];
  const qs = squash(q);
  const qTokens = qn.split(' ').filter(Boolean);
  const scored = [];
  for (const p of all()) {
    const names = [p.name, ...(p.aliases || []), p.area || ''];
    let best = 0;
    for (let i = 0; i < names.length; i++) {
      const n = norm(names[i]);
      if (!n) continue;
      const weight = i === 0 ? 1 : i < names.length - 1 ? 0.95 : 0.6; // name > alias > area text
      const s = squash(names[i]);
      let sc = 0;
      if (n === qn || s === qs) sc = 100;
      else if (n.startsWith(qn) || s.startsWith(qs)) sc = 85;
      else if (n.split(' ').some((w) => w.startsWith(qn))) sc = 70;
      else if (n.includes(qn) || s.includes(qs)) sc = 55;
      else {
        // every word typed by the user must match some word of the place (with small spelling mistakes allowed)
        const words = n.split(' ');
        let ok = true;
        let total = 0;
        for (const t of qTokens) {
          let bestTok = 0;
          for (const w of words) {
            if (w.startsWith(t)) bestTok = Math.max(bestTok, 40);
            else if (t.length >= 4 && w.length >= 4) {
              const maxEd = t.length >= 7 ? 2 : 1;
              if (editDistance(t, w.slice(0, t.length + 1), maxEd) <= maxEd) bestTok = Math.max(bestTok, 30);
            }
          }
          if (!bestTok) { ok = false; break; }
          total += bestTok;
        }
        if (ok) sc = Math.min(50, total / qTokens.length + 5);
        else if (qs.length >= 5 && s.length >= 5 && editDistance(qs, s.slice(0, qs.length + 1), 2) <= 2) sc = 28;
      }
      best = Math.max(best, sc * weight);
    }
    if (best <= 0) continue;
    if (near) best += Math.max(0, 8 - haversine(near, p) / 5000); // closer places rank a little higher
    if (p.category === 'hospital') best += 1;
    scored.push({ p, best });
  }
  scored.sort((a, b) => b.best - a.best);
  return scored.slice(0, limit).map((x) => publicView(x.p, near));
}

function nearby(category, near, limit = 10) {
  let list = all();
  if (category && category !== 'all') list = list.filter((p) => p.category === category);
  if (near) list = list.map((p) => ({ p, d: haversine(near, p) })).sort((a, b) => a.d - b.d).map((x) => x.p);
  else list = list.sort((a, b) => a.name.localeCompare(b.name));
  return list.slice(0, limit).map((p) => publicView(p, near));
}

function save(body, source) {
  const old = body && typeof body.id === 'string' ? store.get('places', body.id) : null;
  const p = toPlace({ ...body, source: source || (old && old.source) || 'admin' }, old);
  return store.put('places', p);
}
const remove = (id) => store.remove('places', id);

// CSV columns: name,category,lat,lng,area,phone,aliases   (aliases separated by | )
function importCsv(text) {
  const lines = String(text || '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  let added = 0;
  const errors = [];
  lines.forEach((line, i) => {
    if (i === 0 && /^name\s*,/i.test(line)) return; // header row
    const c = line.split(',').map((x) => x.trim());
    try {
      save({ name: c[0], category: c[1], lat: c[2], lng: c[3], area: c[4], phone: c[5], aliases: c[6] }, 'admin');
      added++;
    } catch (e) {
      errors.push(`Line ${i + 1}: ${e.message}`);
    }
  });
  return { added, errors };
}

module.exports = { init, search, nearby, save, remove, importCsv, all, norm, CATEGORIES };
