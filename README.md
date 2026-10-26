# AmbuRoute Alert AI - Driver app + Police app + Server (version 2)

Folders:
- `ambulance-server/`    -> Node.js server for Render (database, admin page, alert engine)
- `ambulance_alert_app/` -> Flutter apps (`driver_app`, `police_app`) + GitHub Actions APK build
- `places_template.csv`  -> example file for adding many local places at once
- `SETUP_GUIDE.md`       -> step by step setup for beginners (START HERE)
- `USER_MANUAL.md`       -> manual for drivers, police and admin
- `SUGGESTIONS.md`       -> what is still missing in the project and what to do next

What is new:
1. All app text is simple English. Every button has its own color.
2. Saved local places database: search finds your own hospitals, chowks, markets first.
3. Drivers can tap the map and save a missing place from the app.
4. MongoDB database: places, police posts, ambulances and trip history are saved permanently.
5. Admin page (`/admin`) to enter and edit all data.
6. "How to use" screen inside both apps.

## Version 3 additions
* IoT control (display + buzzer) from both apps, see `IOT_GUIDE.md` and `iot-firmware/`.
* Police app: live ambulance markers + route on the map, ambulance speed, per-button sending (buttons no longer hang).
* Driver app: all online police posts on the map, critical-patient switch, quick messages to police, nearest-hospital button.
* Default server address is now `https://smart-ambulance-mk2n.onrender.com` in both apps.
