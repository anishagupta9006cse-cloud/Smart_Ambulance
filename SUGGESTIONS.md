# What is missing and what to do next

## Must do before real use
1. **Push alerts when the police app is closed.** Today police only get alerts while the app is open. Add Firebase Cloud Messaging (FCM) notifications.
2. **Real login.** Access codes are off by default, so anyone who knows the server address can send fake alerts. Give each driver and officer their own login (the admin page already stores ambulances).
3. **Better map and route service.** The free OSRM, Nominatim and OpenStreetMap tile servers are for demos only and can block heavy use. Use a paid or self-hosted service for real use.
4. **Paid always-on server.** The free Render server sleeps and the first request takes up to 1 minute.
5. **Test on real roads** with a real ambulance and police phones. Only the alert engine and server have automatic tests; the Flutter apps have none.

## Good improvements
- Hospital details: phone number, emergency beds, "Call hospital" button.
- Automatic "nearest hospital" suggestion.
- iOS version (only Android is built now).
- Release signing key and Play Store listing.
- Hindi language option.
- Trip reports and charts in the admin page (trip history is already saved).
- Auto-delete old location data to protect privacy.
- Offline map tiles for weak network areas.
- Rate-limit and logging dashboard.

## Limits to tell people honestly
- The apps do NOT change traffic signals. They only inform police.
- Alerts depend on phone GPS and internet signal.
