# AmbuRoute Alert AI - Driver app + Police app + Server

Folders:
- `ambulance-server/`    -> Node.js server for Render (repo: ambulance-server)
- `ambulance_alert_app/` -> Flutter repo (driver_app, police_app, GitHub Actions APK build)

How it works:
1. Driver chooses start + destination -> the server builds the route and junctions are selected automatically.
2. Driver taps "START EMERGENCY TRIP" -> GPS is sent to the server every 2 seconds.
3. Police only set their own location (traffic area) -> the server detects by itself whether an ambulance route passes through that area.
4. Only posts AHEAD of the ambulance are alerted (forward-only); once the ambulance passes, the alert mutes automatically.
5. Police tap ACKNOWLEDGE / REQUEST LANE CLEARANCE / ESCALATE -> the driver sees it live.
6. Fail-safe: stale GPS or leaving the route PAUSES alerts; manual TEST ALERT button; demo simulation mode.
