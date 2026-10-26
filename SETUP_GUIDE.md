# Setup guide (beginner, step by step)

You need: a GitHub account, a Render account (you already have the server there), a free MongoDB Atlas account.

## PART 1 - Put the new code on GitHub

Server (repo `ambulance-server`):
1. Open your `ambulance-server` repo on github.com.
2. Click **Add file > Upload files**.
3. Unzip this project on your PC. Open the folder `ambulance-server`.
4. Select ALL files inside it (`server.js`, `engine.js`, `db.js`, `places.js`, `package.json`, the `public` and `data` folders, etc.) and drag them into the GitHub page. Do NOT upload `node_modules`.
5. Click **Commit changes**. Render will start deploying by itself.

Apps (repo `ambulance_alert_app`):
1. Open your `ambulance_alert_app` repo on github.com.
2. Click **Add file > Upload files**.
3. Drag everything from the folder `ambulance_alert_app` (`driver_app`, `police_app`, `tools`, `.github`) into the page. If `.github` is hidden, turn on "Show hidden files" in your file explorer.
4. Click **Commit changes**. GitHub Actions will build two APK files (takes about 10 minutes).

## PART 2 - Make a free MongoDB database
1. Go to mongodb.com/atlas and sign up (free).
2. Create a **Free (M0)** cluster. Choose any region close to India (Mumbai if shown).
3. When asked, create a **database user**: type a username and a password. Write both down. Use only letters and numbers in the password.
4. In the left menu open **Network Access > Add IP Address > Allow access from anywhere** (0.0.0.0/0) > Confirm.
5. Go to **Database > Connect > Drivers**. Copy the connection string. It looks like `mongodb+srv://USER:PASSWORD@cluster0.xxxx.mongodb.net/?retryWrites=true&w=majority`.
6. Replace `USER` and `PASSWORD` in it with your own username and password.

## PART 3 - Tell Render about the database
1. Open dashboard.render.com > your server > **Environment**.
2. Add variable `MONGODB_URI` = the connection string from Part 2.
3. Add variable `ADMIN_CODE` = a password you choose for the admin page.
4. Click **Save changes**. Render restarts the server.
5. Open `https://smart-ambulance-mk2n.onrender.com/api/status` in the browser. It must show `"database":"mongodb"`. If it shows `file`, the connection string is wrong - check the Render **Logs** tab.

## PART 4 - Add your local places
1. Open `https://smart-ambulance-mk2n.onrender.com/admin`.
2. Type your ADMIN_CODE and click **Open admin**.
3. In **Places**, click the exact spot on the map (zoom in first), type the name, choose the type, and click **Save place**.
4. Add other spellings in "Other names" (example: `sadar aspatal, civil hospital`) so search works with local words.
5. To add many places: fill `places_template.csv`, copy its lines into the CSV box and click **Import**.
6. Places marked "check location" were added by the developer only roughly. Click Edit, set the right spot on the map, and Save.

## PART 5 - Install the new apps
1. On GitHub open your app repo > **Actions** > latest run > download `driver_app-apk` and `police_app-apk`.
2. Unzip each download, send the `.apk` files to the phones (WhatsApp), and install.
3. Open the app. It now connects to the Render server by default.

## Optional
- Only allow listed ambulances: in Render add `REQUIRE_REGISTERED_AMBULANCE` = `true`, then add ambulances in Admin > Ambulances.
- Keep the free server awake: create a free account on uptimerobot.com and add an HTTP monitor for `https://smart-ambulance-mk2n.onrender.com/health` every 5 minutes.
