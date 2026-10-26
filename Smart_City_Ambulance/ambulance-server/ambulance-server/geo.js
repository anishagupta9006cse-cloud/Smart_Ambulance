'use strict';
// Pure geometry helpers (no dependencies).
const R = 6371000;
const toRad = (d) => (d * Math.PI) / 180;

function haversine(a, b) {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

function buildRoute(points) {
  const cum = [0];
  for (let i = 1; i < points.length; i++) cum.push(cum[i - 1] + haversine(points[i - 1], points[i]));
  return { points, cum, total: cum[cum.length - 1] || 0 };
}

// Project point p onto route segments [startIdx..endIdx]. Returns nearest position along route.
function projectOnRoute(route, p, startIdx = 0, endIdx = Infinity) {
  const pts = route.points;
  if (pts.length < 2) return { idx: 0, t: 0, dist: Infinity, chain: 0 };
  const kx = 111320 * Math.cos(toRad(p.lat));
  const ky = 110540;
  const s = Math.max(0, startIdx);
  const e = Math.min(pts.length - 2, endIdx);
  let best = { idx: s, t: 0, dist: Infinity, chain: route.cum[s] || 0 };
  for (let i = s; i <= e; i++) {
    const ax = (pts[i].lng - p.lng) * kx, ay = (pts[i].lat - p.lat) * ky;
    const bx = (pts[i + 1].lng - p.lng) * kx, by = (pts[i + 1].lat - p.lat) * ky;
    const dx = bx - ax, dy = by - ay;
    const len2 = dx * dx + dy * dy;
    let t = len2 === 0 ? 0 : -(ax * dx + ay * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    const cx = ax + t * dx, cy = ay + t * dy;
    const d = Math.sqrt(cx * cx + cy * cy);
    if (d < best.dist) {
      best = { idx: i, t, dist: d, chain: route.cum[i] + t * (route.cum[i + 1] - route.cum[i]) };
    }
  }
  return best;
}

function routeSlice(route, fromChain, toChain, maxPts = 80) {
  const out = [];
  for (let i = 0; i < route.points.length; i++) {
    if (route.cum[i] >= fromChain && route.cum[i] <= toChain) out.push(route.points[i]);
  }
  if (out.length <= maxPts) return out;
  const step = Math.ceil(out.length / maxPts);
  const thin = out.filter((_, i) => i % step === 0);
  if (thin[thin.length - 1] !== out[out.length - 1]) thin.push(out[out.length - 1]);
  return thin;
}

module.exports = { haversine, buildRoute, projectOnRoute, routeSlice };
