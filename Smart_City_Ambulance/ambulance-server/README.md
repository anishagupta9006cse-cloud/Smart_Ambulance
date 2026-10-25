# AmbuRoute server (Node.js)

## What is new in version 2
- **Database**: places, police posts, ambulances and trip history are saved (MongoDB Atlas, or a local file when MongoDB is not set).
- **Local places search**: the driver app searches your own saved places first (hospitals, chowks, markets...), then the free map search.
- **Admin page** at `https://<your-server>/admin` to add / edit / delete places, police posts and ambulances.
- Police posts that are offline (phone closed) are no longer shown to the driver as "alerted".

## Deploy on Render
- Build Command: `npm install`
- Start Command: `npm start`
- Environment variables: see `.env.example` (`MONGODB_URI` and `ADMIN_CODE` are the important ones)

## Check it works
- `https://<your-server>/health` -> `{"ok":true,...}`
- `https://<your-server>/api/status` -> shows `"database":"mongodb"` when MongoDB is connected
- `https://<your-server>/admin` -> admin login page

## Other optional variables
- `DRIVER_CODE` / `POLICE_CODE`: apps must send this access code
- `REQUIRE_REGISTERED_AMBULANCE=true`: only ambulances added in the admin page can start a trip
- `ALERT_DISTANCE_M` (default 1500), `JUNCTION_GAP_M` (default 300)
- `POST_STALE_SECONDS` (default 180): a police phone that is silent this long is treated as offline

## Tests (no internet needed)
`npm test` runs the alert-engine, places/database and full API tests.
