/*
*******************************************************************************
  Program: OSSMM V1.0.4 - Power Testing (RTC/LFCLK Sampling via RTC2)
  Notes:
  - Sampling driven by RTC2 on LFCLK (32.768 kHz crystal when present)
  - Meets or exceeds target Fs (uses floor(32768/Fs) ticks)
  - Avoids HFCLK-on TIMER, lowers current during BLE connection
*******************************************************************************
*/

/* ----------------------------------------------------------------
   Device Name and Version
  ---------------------------------------------------------------- */
char DeviceName[] = "OSSMM V1.0.4 - Power Testing"; // Version

/* ----------------------------------------------------------------
   Set the Sampling Frequency (Hz). We guarantee >= this rate.
  ---------------------------------------------------------------- */
unsigned int SamplingFrequency = 250; // Hz (actual Fs will be >= this)

/* ------------------- RTC2-DRIVEN SAMPLING (replaces TIMER2) ------------------- */
#include "nrf.h"
volatile bool sample_due = false;
static uint32_t rtc_period_ticks = 0; // ticks per sample, LFCLK 32,768 Hz

/* ----------------------------------------------------------------
   Connection Management Variables
  ---------------------------------------------------------------- */
unsigned long disconnectTime = 0;
const unsigned long RECONNECT_TIMEOUT = 600000;           // 10 minutes
const unsigned long RECONNECT_ADVERTISE_INTERVAL = 5000;  // 5 seconds
unsigned long lastAdvertiseTime = 0;
bool waitingForReconnect = false;
bool intentionalShutdown = false;
unsigned int reconnectAttempts = 0;
const unsigned int MAX_RECONNECT_ATTEMPTS = 120;

/* ----------------------------------------------------------------
   Load Libraries
  ---------------------------------------------------------------- */
#include <bluefruit.h>
#include "Xiao_Sense_LSM6DS3.h"  // Modified LSM6DS3 IMU Library

/* ----------------------------------------------------------------
   Initialize Variables for Sensors, BLE Transmission
  ---------------------------------------------------------------- */
unsigned long Start; // timing vars (kept for your diagnostics)
unsigned long End;
unsigned long TransmitStart;
unsigned long Start2;
unsigned long End2;

bool isConnected = false;
bool initial = false;

uint16_t update_num = 0;      // Transmission number
uint16_t loop_count = 0;      // Messages added to a BLE packet, resets at = X
char mySleepDataPacket[181];  // 180 bytes + null

float gyroData[3] = { 0.0, 0.0, 0.0 };
float accData[3]  = { 0.0, 0.0, 0.0 };

uint16_t gyroVals[3];
uint16_t accVals[3];

uint16_t eog = 0;
uint16_t hr  = 0;

/* ----------------------------------------------------------------
   USB Power and Serial Connection
  ---------------------------------------------------------------- */
bool powerUSB = (NRF_POWER->USBREGSTATUS) & POWER_USBREGSTATUS_VBUSDETECT_Msk;
bool resetButtonLaunch = (NRF_POWER->RESETREAS) & POWER_RESETREAS_RESETPIN_Msk;

/* ----------------------------------------------------------------
    Initialize BLE Variables, Service, and Characteristics
  ---------------------------------------------------------------- */
#define OSSMM_SER_UUID "5aee1a8a-08de-11ed-861d-0242ac120002"
#define OSSMM_CHAR_UUID "405992d6-0cf2-11ed-861d-0242ac120002"
#define OSSMM_MOD_UUID  "1aa00c0d-469a-426b-985c-8299084aed72"
#define OSSMM_POW_UUID  "018ec2b5-7c82-7773-95e2-a5f374275f0b"

BLEService BLEservice = BLEService(OSSMM_SER_UUID);
BLECharacteristic SleepData(OSSMM_CHAR_UUID);
BLECharacteristic SleepModulator(OSSMM_MOD_UUID);
BLECharacteristic PowerControl(OSSMM_POW_UUID);

// Forwards
void sleep_modulator_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);
void power_control_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);
void restartAdvertising();
void handleReconnectionTimeout();
void start_sampling_timer();
void stop_sampling_timer();

/* ----------------------------------------------------------------
  Security and Connection Callbacks (BLE Bonding)
  ---------------------------------------------------------------- */
void connection_secured_callback(uint16_t conn_handle) {
  BLEConnection* connection = Bluefruit.Connection(conn_handle);
  if (connection->secured()) {
    Serial.println("Connection secured: Role = Peripheral");
    ble_gap_addr_t peer_addr = connection->getPeerAddr();
    Serial.print("Peer address: ");
    Serial.print(peer_addr.addr[5], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[4], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[3], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[2], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[1], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[0], HEX);
    Serial.println();

    if (!connection->bonded()) {
      Serial.println("Not bonded yet, requesting pairing");
      connection->requestPairing();
    }
  } else {
    Serial.println("Connection NOT secured");
  }
}

void pair_complete_callback(uint16_t, uint8_t auth_status) {
  if (auth_status == BLE_GAP_SEC_STATUS_SUCCESS) {
    Serial.println("Pairing successful!");
    for (int i = 0; i < 5; i++) {
      analogWrite(LED_BLUE, 0); delay(100);
      analogWrite(LED_BLUE, 255); delay(100);
    }
  } else {
    Serial.print("Pairing failed with status: ");
    Serial.println(auth_status);
  }
}

/* ----------------------------------------------------------------
  BLE Server Callbacks
  ---------------------------------------------------------------- */
void connect_callback(uint16_t conn_handle) {
  BLEConnection* connection = Bluefruit.Connection(conn_handle);
  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name));
  Serial.print("Connected to "); Serial.println(central_name);

  waitingForReconnect = false;
  disconnectTime = 0;
  reconnectAttempts = 0;
  intentionalShutdown = false;

  SleepModulator.write8(0x00);
  PowerControl.write8(0x00);

  delay(1000);
  isConnected = true;
  initial = true;

  start_sampling_timer();   // start periodic sampling (RTC2 / LFCLK)
}

void disconnect_callback(uint16_t, uint8_t reason) {
  Serial.println();
  Serial.print("Disconnected, reason = 0x");
  Serial.println(reason, HEX);

  SleepModulator.write8(0x00);
  PowerControl.write8(0x00);

  isConnected = false;
  initial = true;

  stop_sampling_timer(); // stop RTC2 sampling

  if (intentionalShutdown) {
    Serial.println("Intentional shutdown - going to deep sleep immediately");
    digitalWrite(A4, LOW);
    digitalWrite(A5, LOW);
    NRF_POWER->SYSTEMOFF = 1;
  } else {
    Serial.println("Unexpected disconnect - entering reconnection mode");
    waitingForReconnect = true;
    disconnectTime = millis();
    reconnectAttempts = 0;
    digitalWrite(A5, HIGH);
    restartAdvertising();
    for (int i = 0; i < 3; i++) {
      analogWrite(LED_RED, 128);
      analogWrite(LED_GREEN, 128);
      delay(200);
      analogWrite(LED_RED, 255);
      analogWrite(LED_GREEN, 255);
      delay(200);
    }
  }
}

/* ----------------------------------------------------------------
  Restart Advertising Function
  ---------------------------------------------------------------- */
void restartAdvertising() {
  if (Bluefruit.Advertising.isRunning()) {
    Bluefruit.Advertising.stop();
    delay(100);
  }
  Bluefruit.Advertising.clearData();
  Bluefruit.ScanResponse.clearData();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(BLEservice);
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_GENERIC_WATCH);
  Bluefruit.ScanResponse.addName();

  Bluefruit.Advertising.setInterval(32, 100);
  Bluefruit.Advertising.setFastTimeout(0);
  Bluefruit.Advertising.start(0);

  Serial.println("Advertising restarted for reconnection");
}

/* ----------------------------------------------------------------
  Handle Reconnection Timeout
  ---------------------------------------------------------------- */
void handleReconnectionTimeout() {
  if (!waitingForReconnect) return;
  unsigned long currentTime = millis();
  unsigned long timeSinceDisconnect = currentTime - disconnectTime;

  if (currentTime - lastAdvertiseTime >= RECONNECT_ADVERTISE_INTERVAL) {
    lastAdvertiseTime = currentTime;
    reconnectAttempts++;
    Serial.print("Reconnection attempt #");
    Serial.print(reconnectAttempts);
    Serial.print(" of ");
    Serial.println(MAX_RECONNECT_ATTEMPTS);
    restartAdvertising();
    analogWrite(LED_BLUE, 0);
    delay(50);
    analogWrite(LED_BLUE, 255);
  }

  if (timeSinceDisconnect >= RECONNECT_TIMEOUT || reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    Serial.println("Reconnection timeout reached - going to deep sleep");
    waitingForReconnect = false;
    for (int i = 0; i < 5; i++) {
      digitalWrite(LED_RED, LOW);  delay(500);
      digitalWrite(LED_RED, HIGH); delay(250);
    }
    digitalWrite(A4, LOW);
    digitalWrite(A5, LOW);
    NRF_POWER->SYSTEMOFF = 1;
  }
}

/* ----------------------------------------------------------------
  Connect/Disconnect UI
  ---------------------------------------------------------------- */
void nowConnected() {
  for (int i = 0; i < 8; i++) {
    digitalWrite(LED_GREEN, LOW); delay(250);
    digitalWrite(LED_GREEN, HIGH); delay(250);
  }
  digitalWrite(A5, HIGH);
  digitalWrite(LED_BUILTIN, HIGH);
}

void nowDisconnected() {
  digitalWrite(LED_BUILTIN, HIGH);
}

/* ----------------------------------------------------------------
  Setup
  ---------------------------------------------------------------- */
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("Xiao Sense nRF52840 - OSSMM Application V1.0.4");
  Serial.println("Enhanced with RTC2/LFCLK Sampling");
  delay(500);

  if (!IMU.begin()) {
    Serial.println("Failed to initialize IMU!");
  }
  Serial.println("IMU initialized!");
  Wire.setClock(400000);

  // IO
  pinMode(22, OUTPUT); digitalWrite(22, LOW); // charge 100 mA
  pinMode(A0, INPUT);
  pinMode(A1, INPUT);
  pinMode(A5, OUTPUT); digitalWrite(A5, LOW);
  pinMode(A4, OUTPUT); digitalWrite(A4, LOW);

  // USB/Serial gate
  if (powerUSB) {
    unsigned long serialTimeout = millis() + 10000;
    while (!Serial && (millis() < serialTimeout)) {
      delay(150);
      Serial.println("OSSMM - Serial Connection Attempt...");
      digitalWrite(LED_RED, !digitalRead(LED_RED));
    }
    if (!Serial) {
      for (int i = 0; i < 8; i++) { digitalWrite(LED_RED, LOW); delay(500); digitalWrite(LED_RED, HIGH); delay(250); }
      NRF_POWER->SYSTEMOFF = 1;
    } else {
      Serial.println("OSSMM - Serial Connection Detected");
      digitalWrite(LED_RED, HIGH);
      digitalWrite(LED_GREEN, LOW);
      digitalWrite(LED_BLUE, LOW);
    }
  }

  if (!resetButtonLaunch){
    for (int i = 0; i < 8; i++) { digitalWrite(LED_RED, LOW); delay(500); digitalWrite(LED_RED, HIGH); delay(250); }
    NRF_POWER->SYSTEMOFF = 1;
  }

  // BLE
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.configUuid128Count(15);

  Bluefruit.begin();
  Bluefruit.setTxPower(0);
  Bluefruit.autoConnLed(false);
  Bluefruit.setName(DeviceName);

  Bluefruit.Security.setIOCaps(false, false, false);
  Bluefruit.Security.setPairPasskeyCallback(NULL);
  Bluefruit.Security.setPairCompleteCallback(pair_complete_callback);
  Bluefruit.Security.setSecuredCallback(connection_secured_callback);

  Bluefruit.Periph.setConnectCallback(connect_callback);
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback);
  Bluefruit.Periph.setConnInterval(6, 8); // 7.5 - 15 ms

  BLEservice.begin();

  SleepData.setProperties(CHR_PROPS_NOTIFY);
  SleepData.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
  SleepData.setFixedLen(180);
  SleepData.begin();

  PowerControl.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
  PowerControl.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
  PowerControl.setFixedLen(1);
  PowerControl.begin();
  PowerControl.write8(0x00);
  PowerControl.setWriteCallback(power_control_callback);

  SleepModulator.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
  SleepModulator.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
  SleepModulator.setFixedLen(1);
  SleepModulator.begin();
  SleepModulator.write8(0x00);
  SleepModulator.setWriteCallback(sleep_modulator_callback);

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(BLEservice);
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_GENERIC_WATCH);
  Bluefruit.ScanResponse.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(100, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);

  for (int j = 0; j <= 5; j++) {
    for (int i = 255; i >= 0; i -= 17) { analogWrite(LED_BLUE, i); delay(50); }
  }
  analogWrite(LED_BLUE, 255);
  delay(100);

  Serial.println("Device ready - advertising started");
}

/* ----------------------------------------------------------------
  Main loop
  ---------------------------------------------------------------- */
void loop() {
  if (waitingForReconnect) {
    handleReconnectionTimeout();
    delay(100);
    return;
  }

  if (isConnected == true) {
    if (initial == true) {
      nowConnected();
      initial = false;
    }

    while (isConnected == true) {
      if (sample_due) {
        sample_due = false;

        // IMU
        IMU.readAcceleration(accData[0], accData[1], accData[2]);
        IMU.readGyroscope(gyroData[0], gyroData[1], gyroData[2]);

        for (int i = 0; i < 3; i++) {
          gyroVals[i] = (uint16_t)(gyroData[i] + 2000);
          accVals[i]  = (uint16_t)((accData[i] + 8.0) * 100);
        }

        // ADC
        eog = analogRead(A0);
        hr  = analogRead(A1);

        updateBLE(); // pack + notify every 10 samples (180 B)
      }

      // Let SoftDevice idle CPU/HFCLK until next event
      yield();
    }
  } else {
    if (initial == true) {
      nowDisconnected();
      initial = false;
    }
    delay(100);
  }
}

/* ----------------------------------------------------------------
  BLE Update Function
  ---------------------------------------------------------------- */
void updateBLE() {
  if (loop_count >= 10) {
    SleepData.notify(mySleepDataPacket, 180);
    loop_count = 0;
  } else {
    mySleepDataPacket[(18 * loop_count) + 0]  = (char)(update_num & 0xff);
    mySleepDataPacket[(18 * loop_count) + 1]  = (char)((update_num >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 2]  = (char)(eog & 0xff);
    mySleepDataPacket[(18 * loop_count) + 3]  = (char)((eog >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 4]  = (char)(hr & 0xff);
    mySleepDataPacket[(18 * loop_count) + 5]  = (char)((hr >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 6]  = (char)(accVals[0] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 7]  = (char)((accVals[0] >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 8]  = (char)(accVals[1] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 9]  = (char)((accVals[1] >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 10] = (char)(accVals[2] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 11] = (char)((accVals[2] >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 12] = (char)(gyroVals[0] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 13] = (char)((gyroVals[0] >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 14] = (char)(gyroVals[1] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 15] = (char)((gyroVals[1] >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 16] = (char)(gyroVals[2] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 17] = (char)((gyroVals[2] >> 8) & 0xff);

    update_num++;
    loop_count++;
  }
}

/* ----------------------------------------------------------------
  Sleep Modulator Callback
  ---------------------------------------------------------------- */
void sleep_modulator_callback(uint16_t, BLECharacteristic*, uint8_t* data, uint16_t) {
  Serial.println("Arrived at Sleep Modulator Callback");
  if (data[0]) {
    for (int i = 0; i < 2; i++) {
      for (int j = 0; j < 2; j++) {
        digitalWrite(A4, HIGH); Serial.println("Vibration Motor ON"); delay(400);
        digitalWrite(A4, LOW);  Serial.println("Vibration Motor OFF"); delay(60);
      }
      delay(125);
    }
  }
}

/* ----------------------------------------------------------------
  Power Control Callback
  ---------------------------------------------------------------- */
void power_control_callback(uint16_t, BLECharacteristic*, uint8_t* data, uint16_t) {
  Serial.println("Arrived at Power Control Callback");
  if (data[0] == 2) {
    Serial.println("Received Turn Off command. Shutting down.");
    intentionalShutdown = true;
    digitalWrite(A5, LOW);
    digitalWrite(A4, LOW);
    if (isConnected) {
      for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        BLEConnection* connection = Bluefruit.Connection(conn_hdl);
        if (connection && connection->connected()) {
          connection->disconnect();
          delay(100);
          break;
        }
      }
    }
    NRF_POWER->SYSTEMOFF = 1;
  }
}

/* ----------------------------------------------------------------
  RTC2: ISR + Setup/Teardown (LFCLK @ 32.768 kHz)
  ---------------------------------------------------------------- */

// IRQ handler: schedule next sample and flag work for main loop
extern "C" void RTC2_IRQHandler(void) {
  if (NRF_RTC2->EVENTS_COMPARE[0]) {
    NRF_RTC2->EVENTS_COMPARE[0] = 0;

    // Schedule the next compare relative to the last one
    uint32_t next = (NRF_RTC2->CC[0] + rtc_period_ticks) & 0x00FFFFFF;
    NRF_RTC2->CC[0] = next;

    sample_due = true;
  }
}

// Compute rtc_period_ticks so frequency is >= SamplingFrequency
static uint32_t ticks_for_fs(uint32_t fs_hz) {
  if (fs_hz == 0) fs_hz = 1;
  // ticks = floor(32768 / Fs)  => ensures actual Fs >= target Fs
  uint32_t ticks = (32768UL / fs_hz);
  if (ticks == 0) ticks = 1; // cap at fastest possible (32768 Hz)
  return ticks;
}

void start_sampling_timer() {
  rtc_period_ticks = ticks_for_fs(SamplingFrequency);

  // Stop & clear RTC2
  NRF_RTC2->TASKS_STOP  = 1;
  NRF_RTC2->TASKS_CLEAR = 1;

  // 32.768 kHz LFCLK, prescaler 0
  NRF_RTC2->PRESCALER = 0;

  // First compare: now + period
  uint32_t now = NRF_RTC2->COUNTER & 0x00FFFFFF;
  NRF_RTC2->CC[0] = (now + rtc_period_ticks) & 0x00FFFFFF;

  // Enable compare interrupt
  NRF_RTC2->EVTENSET = RTC_EVTENSET_COMPARE0_Msk;
  NRF_RTC2->INTENSET = RTC_INTENSET_COMPARE0_Msk;

  NVIC_ClearPendingIRQ(RTC2_IRQn);
  NVIC_SetPriority(RTC2_IRQn, 6); // below SoftDevice
  NVIC_EnableIRQ(RTC2_IRQn);

  NRF_RTC2->TASKS_START = 1;

  Serial.print("RTC2 sampling started. ticks=");
  Serial.print(rtc_period_ticks);
  Serial.print(" -> Fs≈ ");
  float fs_actual = 32768.0f / (float)rtc_period_ticks;
  Serial.println(fs_actual, 3);
}

void stop_sampling_timer() {
  NRF_RTC2->INTENCLR = RTC_INTENCLR_COMPARE0_Msk;
  NRF_RTC2->EVTENCLR = RTC_EVTENCLR_COMPARE0_Msk;
  NVIC_DisableIRQ(RTC2_IRQn);
  NRF_RTC2->TASKS_STOP = 1;
  sample_due = false;
}
