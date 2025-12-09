/*
*******************************************************************************
  Notes:
  Program: OSSMM V1.0.4
  By: Jonny Giordano

  Created: Friday July 15th, 2022
  Switch to M5StickC-Plus: Tuesday June 21st, 2022
  Switch to Adafruit Feather Sense: Friday October 25th, 2022
  Working BLE on Adafruit: Monday November 14th, 2022
  Change to Prototype 2L with one EOG sensor
  Switch to Seeed Xiao Sense: Sometime April, 2024?
  Added: April 21st, 2024
  -"Xiao_Sense_LSM6DS3.h" and associated files were taken from the
  Arduino LSM6DS3 library and modified by Github user 'aovestdipaperino'

  Update: November 2nd, 2024
  - Merged Code version with hardware version numbering, to keep things simple

  CRITICAL UPDATE: December 2024
  - Added automatic reconnection support
  - Implemented graceful disconnect handling with timeout
  - Added connection state management
  - Device stays awake for reconnection attempts after disconnect

  Update: April 25th, 2025
  - Added easily adjustable sampling frequency

  Final fixes: April30-May 2nd, 2025
  - Fixed BLE loop error (last 18 bytes were not being sent)
  - Implemented "Just Works" pair bonding

  More fixes: August 24th, 2025
  - Enabled the POW characteristic to shut-off the MCU
  seperately from losing BLE connection. So, now reconnection
  attempts are back.
  - BLE is now AES encrypted, 
  

*******************************************************************************
*/

/* ----------------------------------------------------------------
   Device Name and Version
   - OSSMM VX.X.X
  --------------------------------------------m---------------------
*/
char DeviceName[] = "OSSMM V1.0.4 - Power Testing"; // Version

/* ------------------------------------------------------------------------
   Set the Sampling Frequency
  -------------------------------------------------------------------------
*/
unsigned int SamplingFrequency = 250; // Set Sampling Frequency (Hz)
unsigned int sampling_interval = 0.9 * 1000000  / SamplingFrequency; // Calculate samping interval in microseconds
unsigned long lastSampleTime = 0;

/* ----------------------------------------------------------------
   Connection Management Variables
  -----------------------------------------------------------------
*/
unsigned long disconnectTime = 0;                    // Time when disconnect occurred
const unsigned long RECONNECT_TIMEOUT = 600000;      // 10 minutes timeout for reconnection (600000 ms)
const unsigned long RECONNECT_ADVERTISE_INTERVAL = 5000; // Re-advertise every 5 seconds
unsigned long lastAdvertiseTime = 0;                 // Last time we refreshed advertising
bool waitingForReconnect = false;                    // Flag for reconnection state
bool intentionalShutdown = false;                    // Flag for intentional shutdown via power command
unsigned int reconnectAttempts = 0;                  // Counter for reconnection attempts
const unsigned int MAX_RECONNECT_ATTEMPTS = 120;     // Max attempts (120 * 5sec = 10 minutes)

/* ----------------------------------------------------------------
   Load Libraries
  -----------------------------------------------------------------
*/
#include <bluefruit.h>           // Adafruit Bluetooth Library
#include "Xiao_Sense_LSM6DS3.h"  // Modified LSM6DS3 IMU Library (accelerometer, gyroscope)
//#include <PDM.h>               // microphone library (not yet used)

/* ------------------------------------------------------------------------
   Initialize Variables for Sensors (Accelerometer, Gyroscope, EOG), Timers, BLE Transmission, and Power/Serial Connections
  -------------------------------------------------------------------------
*/
unsigned long Start; // timer variable for measuring code
unsigned long End;              // timer variable for measuring code
unsigned long TransmitStart; // timer variable for measuring measurement+transmission time
unsigned long Start2;           // timer variable for measuring code
unsigned long End2; // timer variable for measuring code

bool isConnected = false;     // If device is connected through BLE
bool initial = false; // If this is the 1st sampling loop on connection/disconnection

uint16_t update_num = 0;      // Transmission number
uint16_t loop_count = 0; // Number of messages added to a BLE packet, resets at = X
char mySleepDataPacket[181]; // Create 'c string' for one transmission, 180 byte + null terminator

float gyroData[3] = { 0.0, 0.0, 0.0 }; // Gyroscope data, [x,y,z] format, range = [-2000,+2000]
float accData[3] = { 0.0, 0.0, 0.0 }; // Accelerometer, [x,y,z] format, range = [-8.0,+8.0]

uint16_t gyroVals[3];         // Formated gyroscope data to [0,+4000], [x,y,z] format
uint16_t accVals[3]; // Formated accelerometer data to [0, 1600], [x,y,z] format

uint16_t eog = 0;             // EOG measurement
uint16_t hr = 0; // Heart Rate (pulse) measurement

/* ----------------------------------------------------------------
   USB Power and Serial Connection
   -----------------------------------------------------------------
*/
bool powerUSB = (NRF_POWER->USBREGSTATUS) & POWER_USBREGSTATUS_VBUSDETECT_Msk; // Determine if receiving power via USB
bool resetButtonLaunch = (NRF_POWER->RESETREAS) & POWER_RESETREAS_RESETPIN_Msk; // Determine if Start-up was due to Reset button ("ON" Button)

/* ----------------------------------------------------------------
    Initialize BLE Variables, Service, and Characteristics
   ----------------------------------------------------------------
*/
#define OSSMM_SER_UUID "5aee1a8a-08de-11ed-861d-0242ac120002"   // Unique Service ID (randomly generated)
#define OSSMM_CHAR_UUID "405992d6-0cf2-11ed-861d-0242ac120002"  // Unique Characteristic ID (randomly generated)
#define OSSMM_MOD_UUID "1aa00c0d-469a-426b-985c-8299084aed72"   // Unique Characteristic ID (randomly generated)
#define OSSMM_POW_UUID "018ec2b5-7c82-7773-95e2-a5f374275f0b"   // Unique Characteristic ID (randomly generated)

BLEService BLEservice = BLEService(OSSMM_SER_UUID); // Service UUID for BLE, generated with random UUID generator
BLECharacteristic SleepData = BLECharacteristic(OSSMM_CHAR_UUID); // Characteristic ID for Sleep Data (IMU, EOG, HR)
BLECharacteristic SleepModulator = BLECharacteristic(OSSMM_MOD_UUID); // Characteristic ID for Sleep Modulator
BLECharacteristic PowerControl = BLECharacteristic(OSSMM_POW_UUID);   // Characteristic ID for Power Control

// Forward declarations for callbacks
void sleep_modulator_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);
void power_control_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);
void restartAdvertising();
void handleReconnectionTimeout();

/* ----------------------------------------------------------------
  Security and Connection Callbacks (BLE Bonding)
  ----------------------------------------------------------------
*/
// Callback when a connection is secured with encryption
void connection_secured_callback(uint16_t conn_handle) {
  BLEConnection* connection = Bluefruit.Connection(conn_handle);
  if (connection->secured()) {
    Serial.println("Connection secured: Role = Peripheral");
    // Get information about the bonded peer
    ble_gap_addr_t peer_addr = connection->getPeerAddr();
    // Print bonded peer address
    /*
    Serial.print("Peer address: ");
    Serial.print(peer_addr.addr[5], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[4], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[3], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[2], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[1], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[0], HEX);
    Serial.println();
    */

    // Request pairing if not already bonded
    if (!connection->bonded()) {
      Serial.println("Not bonded yet, requesting pairing");
      connection->requestPairing();
    }
  } else {
    Serial.println("Connection NOT secured");
  }
}

// Callback when pairing process completes
void pair_complete_callback(uint16_t conn_handle, uint8_t auth_status) {
  if (auth_status == BLE_GAP_SEC_STATUS_SUCCESS) {
    Serial.println("Pairing successful!");
    // Flash blue LED to indicate successful pairing
    for (int i = 0; i < 5; i++) {
      analogWrite(LED_BLUE, 0); // Turn ON Blue LED
      delay(100);
      analogWrite(LED_BLUE, 255); // Turn OFF Blue LED
      delay(100);
    }
  } else {
    Serial.print("Pairing failed with status: ");
    Serial.println(auth_status);
  }
}

/* ----------------------------------------------------------------
  BLE ServerCallBack Functions
  ----------------------------------------------------------------
*/
void connect_callback(uint16_t conn_handle) {
  BLEConnection* connection = Bluefruit.Connection(conn_handle);

  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name));

  Serial.print("Connected to ");
  Serial.println(central_name);

  // Reset reconnection state on successful connection
  waitingForReconnect = false;
  disconnectTime = 0;
  reconnectAttempts = 0;
  intentionalShutdown = false;

  SleepModulator.write8(0x00); // Confirm GATT information of modulation shows it is off
  PowerControl.write8(0x00);   // Confirm GATT information of power control shows it is off

  delay(1000);
  isConnected = true;
  initial = true;
}

void disconnect_callback(uint16_t conn_handle, uint8_t reason) {
  (void)conn_handle;
  (void)reason;

  Serial.println();
  Serial.print("Disconnected, reason = 0x");
  Serial.println(reason, HEX);

  SleepModulator.write8(0x00);
  PowerControl.write8(0x00);

  isConnected = false;
  initial = true;

  // Check if this was an intentional shutdown
  if (intentionalShutdown) {
    Serial.println("Intentional shutdown - going to deep sleep immediately");
    // Turn off power pins
    digitalWrite(A4, LOW);
    digitalWrite(A5, LOW);
    // Enter deep sleep
    NRF_POWER->SYSTEMOFF = 1;
  } else {
    // Unintentional disconnect - enter reconnection mode
    Serial.println("Unexpected disconnect - entering reconnection mode");
    waitingForReconnect = true;
    disconnectTime = millis();
    reconnectAttempts = 0;
    
    // Keep sensors powered for quick reconnection
    digitalWrite(A5, HIGH);
    
    // Ensure advertising is enabled
    restartAdvertising();
    
    // Flash yellow LED pattern to indicate reconnection mode
    for (int i = 0; i < 3; i++) {
      analogWrite(LED_RED, 128);   // Half brightness red
      analogWrite(LED_GREEN, 128); // Half brightness green = yellow
      delay(200);
      analogWrite(LED_RED, 255);   // Turn OFF
      analogWrite(LED_GREEN, 255); // Turn OFF
      delay(200);
    }
  }
}

/* ----------------------------------------------------------------
  Restart Advertising Function
  ----------------------------------------------------------------
*/
void restartAdvertising() {
  // Stop advertising if currently active
  if (Bluefruit.Advertising.isRunning()) {
    Bluefruit.Advertising.stop();
    delay(100);
  }
  
  // Clear any existing advertising data
  Bluefruit.Advertising.clearData();
  Bluefruit.ScanResponse.clearData();
  
  // Re-configure advertising
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(BLEservice);
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_GENERIC_WATCH);
  Bluefruit.ScanResponse.addName();
  
  // Set aggressive advertising intervals for reconnection
  Bluefruit.Advertising.setInterval(32, 100);  // Fast advertising: 20ms to 62.5ms
  Bluefruit.Advertising.setFastTimeout(0);     // Stay in fast mode
  
  // Start advertising indefinitely
  Bluefruit.Advertising.start(0);
  
  Serial.println("Advertising restarted for reconnection");
}

/* ----------------------------------------------------------------
  Handle Reconnection Timeout
  ----------------------------------------------------------------
*/
void handleReconnectionTimeout() {
  if (!waitingForReconnect) return;
  
  unsigned long currentTime = millis();
  unsigned long timeSinceDisconnect = currentTime - disconnectTime;
  
  // Check if we should refresh advertising
  if (currentTime - lastAdvertiseTime >= RECONNECT_ADVERTISE_INTERVAL) {
    lastAdvertiseTime = currentTime;
    reconnectAttempts++;
    
    Serial.print("Reconnection attempt #");
    Serial.print(reconnectAttempts);
    Serial.print(" of ");
    Serial.println(MAX_RECONNECT_ATTEMPTS);
    
    // Refresh advertising to ensure visibility
    restartAdvertising();
    
    // Quick LED flash to show activity
    analogWrite(LED_BLUE, 0);    // Turn ON Blue LED
    delay(50);
    analogWrite(LED_BLUE, 255);  // Turn OFF Blue LED
  }
  
  // Check if timeout has been reached
  if (timeSinceDisconnect >= RECONNECT_TIMEOUT || reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    Serial.println("Reconnection timeout reached - going to deep sleep");
    
    waitingForReconnect = false;
    
    // Flash red LED to indicate giving up
    for (int i = 0; i < 5; i++) {
      digitalWrite(LED_RED, LOW);   // Turn ON Red LED
      delay(500);
      digitalWrite(LED_RED, HIGH);  // Turn OFF Red LED
      delay(250);
    }
    
    // Turn off power pins
    digitalWrite(A4, LOW);
    digitalWrite(A5, LOW);
    
    // Enter deep sleep
    NRF_POWER->SYSTEMOFF = 1;
  }
}

/* ----------------------------------------------------------------
  Connect and Disconnect Functions
  - Blinks LED upon connection/disconnection
  ----------------------------------------------------------------
*/
void nowConnected() {
  for (int i = 0; i < 8; i++) {
    digitalWrite(LED_GREEN, LOW); // Turn the GREEN LED on
    delay(250);
    digitalWrite(LED_GREEN, HIGH); // Turn the GREEN LED off
    delay(250);
  }

  // TURN ON PULSE SENSOR and AD8232
  digitalWrite(A5, HIGH);
  digitalWrite(LED_BUILTIN, HIGH); // Ensure LED is off to save power
}

void nowDisconnected() {
  // Don't flash LEDs here - handled in disconnect_callback
  digitalWrite(LED_BUILTIN, HIGH); // Ensure LED is off to save power
}

void setup() {
  /* ----------------------------------------------------------------
    Initialize Adafruit Feather Sense, IMU
    ----------------------------------------------------------------
  */
  Serial.begin(115200);
  delay(500);
  Serial.println("Xiao Sense nRF52840 - OSSMM Application V1.0.4");
  delay(500);
  
  if (!IMU.begin()) {
    Serial.println("Failed to initialize IMU!");
  }
  Serial.println("IMU initialized!");
  Wire.setClock(400000); // Increase I2C speed to 400 Khz

  /* ----------------------------------------------------------------
      Initialize INPUT, CHARGING, POWER, and LED Pins
     ----------------------------------------------------------------
  */
  // Battery Charging
  pinMode(22, OUTPUT);
  digitalWrite(22, LOW); // Set LOW -> 100 mA charge

  // AD8232 PINS
  pinMode(A0, INPUT); // EOG/EEG analog signal

  // Heartrate Sensor
  pinMode(A1, INPUT); // Heartrate monitor analog signal

  // Power pin (Delivers power to AD8232 and HR Sensor)
  pinMode(A5, OUTPUT);
  digitalWrite(A5, LOW);

  // Vibration Disc
  pinMode(A4, OUTPUT);
  digitalWrite(A4, LOW);

  /* ----------------------------------------------------------------
      Detect USB Charging vs Serial Connection - Detect Start-Up Reason
     ----------------------------------------------------------------
  */
  // Check if USB Power is for Charging or for Serial Connection
  if (powerUSB) {
    unsigned long serialTimeout = millis() + 10000; // Wait 10 Seconds for Serial Connection

    while (!Serial && (millis() < serialTimeout)) {
      delay(150);
      Serial.println("OSSMM - Serial Connection Attempt...");
      digitalWrite(LED_RED, !digitalRead(LED_RED));
    }

    if (!Serial) {
      for (int i = 0; i < 8; i++) {
        digitalWrite(LED_RED, LOW);
        delay(500);
        digitalWrite(LED_RED, HIGH);
        delay(250);
      }
      NRF_POWER->SYSTEMOFF = 1; // USB Power only, go to sleep!
    }
    else {
      Serial.println("OSSMM - Serial Connection Detected");
      digitalWrite(LED_RED, HIGH);
      digitalWrite(LED_GREEN, LOW);
      digitalWrite(LED_BLUE, LOW);
    }
  }

  // Check if Start-up was Intentional
  if (!resetButtonLaunch){
    for (int i = 0; i < 8; i++) {
        digitalWrite(LED_RED, LOW);
        delay(500);
        digitalWrite(LED_RED, HIGH);
        delay(250);
    }
    NRF_POWER->SYSTEMOFF = 1;
  }

  /* ----------------------------------------------------------------
      Initialize Bluetooth Low Energy (BLE) with Security
     ----------------------------------------------------------------
  */
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.configUuid128Count(15);

  Bluefruit.begin();
  Bluefruit.setTxPower(0);              // Set 0dB for better battery life
  Bluefruit.autoConnLed(false);
  Bluefruit.setName(DeviceName);

  // Configure security for "Just Works" pairing
  Bluefruit.Security.setIOCaps(false, false, false);
  Bluefruit.Security.setPairPasskeyCallback(NULL);
  Bluefruit.Security.setPairCompleteCallback(pair_complete_callback);
  Bluefruit.Security.setSecuredCallback(connection_secured_callback);

  Bluefruit.Periph.setConnectCallback(connect_callback);
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback);
  Bluefruit.Periph.setConnInterval(6, 8); // 7.5 - 15 ms

  BLEservice.begin();

  // Configure SLEEP DATA Characteristic
  SleepData.setProperties(CHR_PROPS_NOTIFY);
  SleepData.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);
  SleepData.setFixedLen(180);
  SleepData.begin();

  // Configure POWER CONTROL Characteristic
  PowerControl.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
  PowerControl.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
  PowerControl.setFixedLen(1);
  PowerControl.begin();
  PowerControl.write8(0x00);
  PowerControl.setWriteCallback(power_control_callback);

  // Configure SLEEP MODULATOR Characteristic
  SleepModulator.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
  SleepModulator.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);
  SleepModulator.setFixedLen(1);
  SleepModulator.begin();
  SleepModulator.write8(0x00);
  SleepModulator.setWriteCallback(sleep_modulator_callback);

  // Advertising configuration
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(BLEservice);
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_GENERIC_WATCH);
  Bluefruit.ScanResponse.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(100, 244); // Normal advertising
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0); // Don't stop advertising

  // Startup complete LED sequence
  for (int j = 0; j <= 5; j++) {
    for (int i = 255; i >= 0; i = i - 17) {
      analogWrite(LED_BLUE, i);
      delay(50);
    }
  }
  analogWrite(LED_BLUE, 255);
  delay(100);
  
  Serial.println("Device ready - advertising started");
}

void loop() {
  /*-----------------------------------------------------------------
     Handle reconnection timeout if waiting for reconnect
    -----------------------------------------------------------------
  */
  if (waitingForReconnect) {
    handleReconnectionTimeout();
    delay(100); // Small delay while waiting for reconnection
    return; // Skip normal loop processing
  }
  
  /*-----------------------------------------------------------------
     Check if BLE is connected, and if initial loop
    -----------------------------------------------------------------
  */
  if (isConnected == true) {
    if (initial == true) {
      nowConnected();
      initial = false;
      lastSampleTime = micros();
    }

    while (isConnected == true) {
      /*-----------------------------------------------------------------
          Collect Measurements using precise timing at set frequency
        -----------------------------------------------------------------
      */
      unsigned long currentTime = micros();
      if (currentTime - lastSampleTime >= sampling_interval) {

        if (currentTime - lastSampleTime >= 2 * sampling_interval) {
          lastSampleTime = currentTime;
        }
        else {
          lastSampleTime = lastSampleTime + sampling_interval;
        }

        // Get IMU Data
        IMU.readAcceleration(accData[0], accData[1], accData[2]);
        IMU.readGyroscope(gyroData[0], gyroData[1], gyroData[2]);

        // Convert IMU Data
        for (int i = 0; i < 3; i++) {
          gyroVals[i] = (uint16_t)(gyroData[i] + 2000);
          accVals[i] = (uint16_t)((accData[i] + 8.0) * 100);
        }

        // Get ADC data
        eog = analogRead(A0);
        hr = analogRead(A1);

        /* ----------------------------------------------------------------
            BLE Update
           ----------------------------------------------------------------
        */
        updateBLE();
      }

      yield(); // Give other system tasks a chance to run
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
    BLE Update Function ( Optimized transmission is inspired by Souichirou Kikuchi M5StickC BLE project)
   ----------------------------------------------------------------
*/
void updateBLE() {
  if (loop_count >= 10) {
    SleepData.notify(mySleepDataPacket, 180);
    loop_count = 0;
  } else {
    mySleepDataPacket[(18 * loop_count) + 0] = (char)(update_num & 0xff);
    mySleepDataPacket[(18 * loop_count) + 1] = (char)((update_num >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 2] = (char)(eog & 0xff);
    mySleepDataPacket[(18 * loop_count) + 3] = (char)((eog >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 4] = (char)(hr & 0xff);
    mySleepDataPacket[(18 * loop_count) + 5] = (char)((hr >> 8) & 0xff);
    mySleepDataPacket[(18 * loop_count) + 6] = (char)(accVals[0] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 7] = ((char)((accVals[0] >> 8) & 0xff));
    mySleepDataPacket[(18 * loop_count) + 8] = ((char)(accVals[1] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 9] = ((char)((accVals[1] >> 8) & 0xff));
    mySleepDataPacket[(18 * loop_count) + 10] = ((char)(accVals[2] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 11] = ((char)((accVals[2] >> 8) & 0xff));
    mySleepDataPacket[(18 * loop_count) + 12] = ((char)(gyroVals[0] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 13] = ((char)((gyroVals[0] >> 8) & 0xff));
    mySleepDataPacket[(18 * loop_count) + 14] = ((char)(gyroVals[1] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 15] = ((char)((gyroVals[1] >> 8) & 0xff));
    mySleepDataPacket[(18 * loop_count) + 16] = ((char)(gyroVals[2] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 17] = ((char)((gyroVals[2] >> 8) & 0xff));

    update_num++;
    loop_count++;
  }
}

/* ----------------------------------------------------------------
    Sleep Modulator Callback
   ----------------------------------------------------------------
*/
void sleep_modulator_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  Serial.println("Arrived at Sleep Modulator Callback");
  (void)conn_hdl;
  (void)chr;
  (void)len;

  if (data[0]) {
    for (int i = 0; i < 2; i++) {
      for (int j = 0; j < 2; j++) {
        digitalWrite(A4, HIGH);
        Serial.println("Vibration Motor ON");
        delay(400);
        digitalWrite(A4, LOW);
        Serial.println("Vibration Motor OFF");
        delay(60);
      }
      delay(125);
    }
  }
}

/* ----------------------------------------------------------------
    Power Control Callback
   ----------------------------------------------------------------
*/
void power_control_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  Serial.println("Arrived at Power Control Callback");
  (void)conn_hdl;
  (void)chr;
  (void)len;

  // data = 2 -> Turn Off Device
  if (data[0] == 2) {
    Serial.println("Received Turn Off command. Shutting down.");
    
    // Set flag for intentional shutdown
    intentionalShutdown = true;
    
    // Turn off power to external sensors and vibration motor
    digitalWrite(A5, LOW);
    digitalWrite(A4, LOW);
    
    // Disconnect if connected
    if (isConnected) {
      // Find the connection handle and disconnect
      for (uint16_t conn_hdl = 0; conn_hdl < BLE_MAX_CONNECTION; conn_hdl++) {
        BLEConnection* connection = Bluefruit.Connection(conn_hdl);
        if (connection && connection->connected()) {
          connection->disconnect();
          delay(100); // Give time for disconnect to process
          break;
        }
      }
    }
    
    // Go to deep sleep
    NRF_POWER->SYSTEMOFF = 1;
  }
}
