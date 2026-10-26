# IoT guide (display + buzzer)

## How it works
```
Police app / Driver app  ->  Server (Render)  <-  ESP32 device asks every 1.5 s
```
* The apps send a command ("show this text", "ring the buzzer") to the server.
* The ESP32 asks `GET /api/iot/<DEVICE_ID>/state` and shows / rings what the server says.
* **Device ID**
  * Police post device: the post ID. The police app fills it in by itself (IoT CONTROL button).
  * Ambulance device: the ambulance number, for example `AMB-101`.
* **Auto mode (police post device only):** when an ambulance is coming, the server itself shows
  "AMBULANCE COMING / CLEAR THE ROAD" with a beep, changes to a siren when it is very close, and switches
  everything off after the ambulance has passed. A critical patient shows "CRITICAL PATIENT".
  A manual command from the app keeps auto mode quiet for 60 seconds. Auto mode can be switched off in the app.
* **Safety:** a buzzer never rings for more than 60 seconds from one command, auto alerts switch off by
  themselves 15 seconds after the last ambulance GPS update, and the ESP32 sketch stops the buzzer if it
  cannot reach the server for 10 seconds.

## Apps
* **Police app:** top bar button `IOT CONTROL` (or menu). Preset messages, own message, clear display,
  Beep / Siren / Long tone / Stop buzzer, auto mode switch, device online status.
* **Driver app:** `IOT CONTROL` button. Switch at the top: `My device` (ambulance device) or
  `Police on route` (all police post devices that are on your route, ahead of you).
  Driver app only: `Critical patient` switch, `MESSAGE POLICE`, `NEAREST HOSPITAL`.

## Server API (for your own hardware)
| What | Call |
| --- | --- |
| Device asks what to do | `GET /api/iot/<id>/state` -> `{ display:{on,text}, buzzer:{on,pattern}, seq }` |
| Status for apps | `GET /api/iot/<id>` |
| Command | `POST /api/iot/<id>/command` body `{ "display":{"text":"HELLO","seconds":120}, "buzzer":{"pattern":"beep","seconds":20}, "auto":true }` |
| Clear display / stop buzzer | `{ "display": null }` / `{ "buzzer": {"pattern":"off"} }` |
| Driver -> police devices on route | `POST /api/trips/<tripId>/iot` (same body) |
| Admin list of devices | `GET /api/admin/iot` with header `x-admin-code` |

`pattern` is `beep`, `siren` or `continuous`. If `DRIVER_CODE` / `POLICE_CODE` are set on the server, the device
must send one of them in the header `x-access-code`.

## Test on your bench
1. Open `esp32_device.ino` (folder `iot-firmware/esp32_device`), write your WiFi, the device ID, upload.
2. Open the police app -> IOT CONTROL -> the chip must say "Device is online".
3. Tap a preset message and BEEP. The LCD must change and the buzzer must beep.
4. Driver app: start a trip in Practice mode, tap TEST ALERT. The police device shows "TEST ALERT" for a few seconds.
