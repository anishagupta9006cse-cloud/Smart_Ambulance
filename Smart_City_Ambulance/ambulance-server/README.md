# AmbuRoute server (Node.js)

Deploy on Render:
- Build Command: `npm install`
- Start Command: `npm start`
- Environment: `NODE_VERSION` = `20`

Optional environment variables:
- `DRIVER_CODE` / `POLICE_CODE`: if set, the apps must send this access code
- `ALERT_DISTANCE_M`: distance at which a post is alerted (default 1500)
- `JUNCTION_GAP_M`: minimum distance between auto-selected junctions (default 300)

Check: open `https://<your-server-url>/health` in a browser -> `{"ok":true,...}`

Local test (no internet / npm install needed): `node test-engine.js`
