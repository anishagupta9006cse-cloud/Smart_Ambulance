# AmbuRoute Alert AI - User Manual

## 1. What is this system?
AmbuRoute helps an ambulance reach the hospital faster. The driver chooses a hospital. The app makes the route and shares the ambulance location. Traffic police posts on that route get a voice and vibration alert before the ambulance arrives, and can answer the driver.

There are three parts: **Driver app**, **Police app**, **Admin page**.

## 2. Driver app
### First time
1. Open the app. Type your name and ambulance number (example AMB-101). Tap **CONTINUE**.
2. Allow Location. Keep phone GPS on.
### Making a trip
1. Tap the top box "Where do you want to go?".
2. Type the hospital name, or tap **Hospitals** to see saved hospitals near you. Tap one.
3. If the place is not found: tap the map at the exact spot, tap **SAVE THIS PLACE FOR NEXT TIME**, type the name and type, tap Save.
4. Tap **SELECT THIS PLACE**.
5. Check the blue route and orange junction dots. Tap **START EMERGENCY TRIP**.
### During the trip
- Keep the app open. Voice tells you the next junction.
- Police posts on your way show colors: blue Waiting, orange Police alerted, red Very close, green Police saw it, grey Crossed.
- **TEST ALERT** sends a test to online police posts.
- **FIND NEW ROUTE** appears if you leave the route.
- **STOP TRIP** ends the trip. It also ends by itself at the destination.
### Practice mode
Before starting, switch on "Practice mode" to test at home. The ambulance moves by itself.

## 3. Police app
1. Type your name and post name. Tap **USE MY GPS** at your post, or **CHOOSE ON MAP**.
2. Choose alert distance (300 m small chowk, 1200 m big junction). Tap **START DUTY**.
3. Keep the app open with the screen on.
4. When an ambulance comes you hear a voice and feel vibration. The card shows distance and time.
5. Tap **I SAW IT**, **CLEARING THE LANE** or **NEED HELP**. The driver sees it.
6. After the ambulance passes, the alert turns off by itself.
7. Menu > **Finish duty** at the end of the shift.
The buttons only send a message. They do not change traffic lights.

## 4. Admin page
Open `https://<your-server>/admin` and enter the admin code.
- **Places**: add, edit, delete hospitals, chowks, markets. Click the map for the exact spot. Add other names. Import many by CSV.
- **Police posts**: see online/offline posts, fix a location, delete.
- **Ambulances**: add ambulance numbers and drivers. Block an ambulance.
- **Trip history**: last 100 trips.

## 5. Problems and answers
- "Cannot reach the server": wait 1 minute and tap try again (free server wakes up slowly).
- Place not found: tap the map and save it, or ask admin to add it.
- No voice: raise phone volume, use Menu > Test sound and voice (police).
- No police alert: police app must be open and showing "Watching for ambulances".
- "Not registered" error: ask the admin to add your ambulance number.
