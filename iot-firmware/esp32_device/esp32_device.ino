// AmbuRoute IoT device (ESP32 + 16x2 I2C LCD + active buzzer)
//
// What it does: every 1.5 seconds it asks the server what to show / ring, then drives the LCD and the buzzer.
// The police app and the driver app send the commands. In "auto mode" the server also switches this device
// by itself when an ambulance is coming to the police post that has the same ID.
//
// NOTE: this sketch was written together with the apps but was NOT tested on real hardware here.
//       Test on your bench first (see IOT_GUIDE.md).
//
// Libraries (Arduino Library Manager): "ArduinoJson" (v7), "LiquidCrystal I2C" (Frank de Brabander).
// Board: "ESP32 Dev Module".
//
// Wiring:   LCD SDA -> GPIO21, LCD SCL -> GPIO22, LCD VCC -> 5V, LCD GND -> GND
//           Buzzer (+) -> GPIO25 (through a small transistor if the buzzer takes more than 20 mA), Buzzer (-) -> GND

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// ----------- CHANGE THESE -----------
const char* WIFI_SSID     = "YOUR_WIFI_NAME";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
const char* SERVER_URL    = "https://smart-ambulance-mk2n.onrender.com";
// Device ID: for a police post use the POST ID (the app shows it in the IoT panel, default value).
// For an ambulance use the ambulance number, for example AMB-101. Letters, numbers, - and _ only.
const char* DEVICE_ID     = "PUT_DEVICE_ID_HERE";
// Only if you set DRIVER_CODE or POLICE_CODE on the server, write one of them here. Otherwise leave empty.
const char* ACCESS_CODE   = "";
// ------------------------------------

const int BUZZER_PIN = 25;
const int LCD_ADDR   = 0x27;   // some LCD boards use 0x3F
const unsigned long POLL_MS = 1500;
const unsigned long FAILSAFE_MS = 10000; // no answer from the server for 10 s => buzzer OFF

LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);

String shownText = "\x01";   // something that can never match, so the first text is drawn
String pattern = "off";
bool buzzerWanted = false;
unsigned long lastOk = 0;
unsigned long lastPoll = 0;

void drawText(const String& text) {
  String l1 = text, l2 = "";
  int nl = text.indexOf('\n');
  if (nl >= 0) { l1 = text.substring(0, nl); l2 = text.substring(nl + 1); }
  l1 = (l1 + "                ").substring(0, 16);
  l2 = (l2 + "                ").substring(0, 16);
  lcd.setCursor(0, 0); lcd.print(l1);
  lcd.setCursor(0, 1); lcd.print(l2);
}

void idleScreen() {
  drawText(String("AmbuRoute IoT\n") + (WiFi.status() == WL_CONNECTED ? "Ready" : "No WiFi"));
}

void connectWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) delay(250);
}

// beep = short pulses, siren = fast pulses, continuous = always on
void driveBuzzer() {
  bool on = false;
  unsigned long m = millis();
  if (buzzerWanted) {
    if (pattern == "continuous") on = true;
    else if (pattern == "siren") on = (m / 120) % 2 == 0;
    else on = (m / 250) % 2 == 0; // beep
  }
  digitalWrite(BUZZER_PIN, on ? HIGH : LOW);
}

void poll() {
  connectWifi();
  if (WiFi.status() != WL_CONNECTED) return;

  WiFiClientSecure client;
  client.setInsecure(); // simple for a demo. For real use, load the server certificate instead.
  HTTPClient http;
  String url = String(SERVER_URL) + "/api/iot/" + DEVICE_ID + "/state";
  if (!http.begin(client, url)) return;
  http.setTimeout(8000);
  if (strlen(ACCESS_CODE) > 0) http.addHeader("x-access-code", ACCESS_CODE);

  int code = http.GET();
  if (code == 200) {
    JsonDocument doc;
    if (!deserializeJson(doc, http.getString())) {
      bool dispOn = doc["display"]["on"] | false;
      String text = doc["display"]["text"] | "";
      buzzerWanted = doc["buzzer"]["on"] | false;
      pattern = String((const char*)(doc["buzzer"]["pattern"] | "off"));
      String want = dispOn ? text : String("\x02");   // \x02 = idle screen
      if (want != shownText) {
        shownText = want;
        if (dispOn) drawText(text); else idleScreen();
      }
      lastOk = millis();
    }
  }
  http.end();
}

void setup() {
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();
  drawText("AmbuRoute IoT\nConnecting...");
  connectWifi();
  idleScreen();
  lastOk = millis();
}

void loop() {
  if (millis() - lastPoll >= POLL_MS) {
    lastPoll = millis();
    poll();
  }
  // fail-safe: if the server cannot be reached, never leave the buzzer ringing
  if (millis() - lastOk > FAILSAFE_MS) buzzerWanted = false;
  driveBuzzer();
}
