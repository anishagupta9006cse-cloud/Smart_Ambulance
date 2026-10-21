'use strict';
const { haversine, buildRoute, projectOnRoute } = require('./geo');

const OSRM = process.env.OSRM_URL || 'https://router.project-osrm.org';
const NOMINATIM = process.env.NOMINATIM_URL || 'https://nominatim.openstreetmap.org';
const UA = 'AmbuRouteAlertAI/1.0 (hackathon prototype)';
const GEO_COUNTRY = process.env.GEO_COUNTRY === undefined ? 'in' : process.env.GEO_COUNTRY;
const JUNCTION_GAP_M = Number(process.env.JUNCTION_GAP_M) || 300;

async function fetchJson(url, timeoutMs = 12000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' }, signal: ctrl.signal });
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

function pickJunctions(cands, route) {
  const withChain = cands
    .map((c) => ({ ...c, chain: projectOnRoute(route, c).chain }))
    .filter((c) => c.chain > 40 && c.chain < route.total - 40)
    .sort((a, b) => a.chain - b.chain);
  const gap = Math.max(JUNCTION_GAP_M, route.total / 60); // max ~60 junctions
  const out = [];
  let last = -Infinity;
  for (const c of withChain) {
    if (c.chain - last >= gap) {
      out.push(c);
      last = c.chain;
    }
  }
  return out.map((c, i) => ({
    id: 'J' + (i + 1),
    name: c.road ? `Junction ${i + 1} (${c.road})` : `Junction ${i + 1}`,
    lat: c.lat,
    lng: c.lng,
    chain: Math.round(c.chain),
  }));
}

function extractJunctions(osrmRoute, route) {
  const turnTypes = ['turn', 'end of road', 'fork', 'roundabout', 'rotary', 'merge', 'on ramp', 'off ramp'];
  const cands = [];
  for (const leg of osrmRoute.legs || []) {
    for (const step of leg.steps || []) {
      const manType = step.maneuver && step.maneuver.type;
      (step.intersections || []).forEach((it, k) => {
        const real = (it.bearings && it.bearings.length >= 3) || (k === 0 && turnTypes.includes(manType));
        if (!real || !it.location) return;
        cands.push({ lat: it.location[1], lng: it.location[0], road: step.name || '' });
      });
    }
  }
  return pickJunctions(cands, route);
}

function fallbackRoute(from, to) {
  const total = haversine(from, to);
  const n = Math.max(2, Math.ceil(total / 25));
  const points = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    points.push({ lat: from.lat + (to.lat - from.lat) * t, lng: from.lng + (to.lng - from.lng) * t });
  }
  const route = buildRoute(points);
  const cands = [];
  for (let d = 400; d < route.total - 100; d += 400) {
    const t = d / route.total;
    cands.push({ lat: from.lat + (to.lat - from.lat) * t, lng: from.lng + (to.lng - from.lng) * t, road: '' });
  }
  const junctions = pickJunctions(cands, route).map((j, i) => ({ ...j, name: `Checkpoint ${i + 1}` }));
  return { route, junctions, distance: route.total, duration: route.total / 9, fallback: true };
}

async function getRoute(from, to) {
  try {
    const url = `${OSRM}/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}?overview=full&geometries=geojson&steps=true`;
    const data = await fetchJson(url, 15000);
    if (data.code !== 'Ok' || !data.routes || !data.routes[0]) throw new Error(data.message || data.code || 'no route');
    const r = data.routes[0];
    const points = r.geometry.coordinates.map((c) => ({ lat: c[1], lng: c[0] }));
    if (points.length < 2) throw new Error('empty geometry');
    const route = buildRoute(points);
    return { route, junctions: extractJunctions(r, route), distance: r.distance, duration: r.duration, fallback: false };
  } catch (e) {
    console.warn('OSRM failed -> fallback route:', e.message);
    return fallbackRoute(from, to);
  }
}

// ---- geocoding (Nominatim, 1 req/sec + cache) ----
const geoCache = new Map();
let lastGeoCall = 0;
async function geocode(q, near) {
  const key = q.toLowerCase() + '|' + (near ? near.lat.toFixed(1) + ',' + near.lng.toFixed(1) : '');
  const hit = geoCache.get(key);
  if (hit && Date.now() - hit.t < 10 * 60 * 1000) return hit.v;
  const wait = lastGeoCall + 1100 - Date.now();
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastGeoCall = Date.now();
  const params = new URLSearchParams({ q, format: 'jsonv2', limit: '6' });
  if (GEO_COUNTRY) params.set('countrycodes', GEO_COUNTRY);
  if (near) params.set('viewbox', `${near.lng - 0.6},${near.lat + 0.6},${near.lng + 0.6},${near.lat - 0.6}`);
  const data = await fetchJson(`${NOMINATIM}/search?${params.toString()}`, 10000);
  const v = (Array.isArray(data) ? data : [])
    .map((d) => ({ name: String(d.display_name || ''), lat: Number(d.lat), lng: Number(d.lon) }))
    .filter((d) => isFinite(d.lat) && isFinite(d.lng));
  geoCache.set(key, { t: Date.now(), v });
  return v;
}

module.exports = { getRoute, geocode, fallbackRoute };
