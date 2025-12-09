/*
*******************************************************************************
  Notes:
  Program: OSSMM V1.0.3
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

  Update: April 25th, 2025
  - Added easily adjustable sampling frequency

  Final fixes: April30-May 2nd, 2025
  - Fixed BLE loop error (last 18 bytes were not being sent)
  - Implemented "Just Works" pair bonding

  One more fix: August 24th, 2025
  -Enabled the POW characteristic to shut-off the MCU
  seperately from losing BLE connection. This gives robustness
  to the connection if it is ever lost.

  Other:
  Things that would be *nice* to do:
  - Temperature Sensor check, and automatic shut down
  on preset temperature limt, with warning alarm warning
  notification to the OSSMM app
  - Battery measurement and indicator code


*******************************************************************************
*/

/* ----------------------------------------------------------------
   Device Name and Version
   - OSSMM VX.X.X
  --------------------------------------------m---------------------
*/
char DeviceName[] = "OSSMM V1.0.4"; // Version


/* ------------------------------------------------------------------------
   Set the Sampling Frequency
  -------------------------------------------------------------------------
*/

unsigned int SamplingFrequency = 250; // Set Sampling Frequency (Hz)
unsigned int sampling_interval = 1.10 * 1000000  / SamplingFrequency; // Calculate samping interval in microseconds ( Adustment Factor * (1 / Sampling Frequency)* 1000000 microseconds ) Note: The Xiao Sense nRF52840 does not have a crystal, so timing will drift (e.g., due to temeprature). We add an adjustment factor to get *at least* the desired sampling frequency.

unsigned long lastSampleTime = 0;
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
#define OSSMM_POW_UUID "018ec2b5-7c82-7773-95e2-a5f374275f0b"   // Unique Characteristic ID (randomly generated) (not needed since DEEP SLEEP is enabled on BLE disconnect)

// 405992d6-0cf2-11ed-861d-0242ac120002
// 018ec2b5-7c82-7773-95e2-a5f374275f0b
// 282f6378-5781-43ce-9e2c-24cec9aaeb27

BLEService BLEservice = BLEService(OSSMM_SER_UUID); // Service UUID for BLE, generated with random UUID generator
BLECharacteristic SleepData = BLECharacteristic(OSSMM_CHAR_UUID); // Characteristic ID for Sleep Data (IMU, EOG, HR), generated with random UUID generator
BLECharacteristic SleepModulator = BLECharacteristic(OSSMM_MOD_UUID); // Characteristic ID for Sleep Modulator (In Version 1 Vibration Disc), generated with random UUID generator
BLECharacteristic PowerControl = BLECharacteristic(OSSMM_POW_UUID);   // Characteristic ID for Power Control

// Forward declarations for callbacks
void sleep_modulator_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);
void power_control_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len);


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
    Serial.print("Peer address: ");
    Serial.print(peer_addr.addr[5], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[4], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[3], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[2], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[1], HEX); Serial.print(":");
    Serial.print(peer_addr.addr[0], HEX);
    Serial.println();

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
  BLEConnection* connection = Bluefruit.Connection(conn_handle); // Get the reference to current connection

  char central_name[32] = { 0 };
  connection->getPeerName(central_name, sizeof(central_name)); // Get name of client device (i.e. Android device w/ OSSMM app)

  Serial.print("Connected to ");
  Serial.println(central_name);

  SleepModulator.write8(0x00); // Confirm GATT information of modulation shows it is off
  PowerControl.write8(0x00);   // Confirm GATT information of power control shows it is off

  // delay for request to complete
  delay(1000);
  isConnected = true;  // Set 'connection' to TRUE
  initial = true; // Set 'initial' to TRUE as this will be first loop while connected
}

void disconnect_callback(uint16_t conn_handle, uint8_t reason) {
  (void)conn_handle;
  (void)reason;

  Serial.println();
  Serial.print("Disconnected, reason = 0x");
  Serial.println(reason, HEX);

  SleepModulator.write8(0x00);  // Confirm GATT information of modulation shows it is off
  PowerControl.write8(0x00);    // Confirm GATT information of power control shows it is off

  isConnected = false;
  initial = true;       // Set 'initial' to TRUE as this will be first loop on re-connection (not needed, but added as safety)


  //TURN OF XIAO SENSE (DEEP SLEEP) AND POWER PINS
  //Serial.println("Turning off power pins!");
  //digitalWrite(A4, LOW);                                      // Set A4 pin to OFF (No Signal to Vibration Motor)
  //digitalWrite(A5, LOW); // Set A5 pin to OFF (No Power to AD8232 or Pulse Sensor)

  //Serial.println("Going to sleep....good night!");
  //NRF_POWER->SYSTEMOFF = 1;
}

/* ----------------------------------------------------------------
  Connect and Disconnect Functions
  - Blinks red LED upon connection/disconenction
  ----------------------------------------------------------------
*/

void nowConnected() {
  for (int i = 0; i < 8; i++) {
    digitalWrite(LED_GREEN, LOW); // Turn the GREEN LED on
    delay(250); // Wait for a quarter second
    digitalWrite(LED_GREEN, HIGH); // Turn the GREEN LED off
    delay(250);
  }

  // TURN ON PULSE SENSOR and AD8232
  digitalWrite(A5, HIGH); // Set A5 pin to OFF (No Power to AD8232 or Pulse Sensor)
  digitalWrite(LED_BUILTIN, HIGH); // Ensure LED is off to save power (Xiao nRF52840 Sense LEDs have reverse logic, so HIGH=>LOW)
}

void nowDisconnected() {
  for (int i = 0; i < 8; i++) {
    digitalWrite(LED_RED, LOW); // Turn the RED LED on
    delay(500); // Wait for a quarter second
    digitalWrite(LED_RED, HIGH); // Turn the RED LED off
    delay(250);
  }

  digitalWrite(LED_BUILTIN, HIGH); // Ensure LED is off to save power (Xiao nRF52840 Sense has reverse logic, so HIGH=>LOW)
}

void setup() {

  /* ----------------------------------------------------------------
    Initialize Adafruit Feather Sense, IMU
    ----------------------------------------------------------------
  */
  Serial.begin(115200);
  delay(500);                                                    // Give device time to connect to Serial
  Serial.println("Xiao Sense nRF52840 - OSSMM Application");
  delay(500);
  if (!IMU.begin()) {  // Initialize IMU (Accelerometer, Gyroscope)
    Serial.println("Failed to initialize IMU!");
  }
  Serial.println("IMU initialized!");
  Wire.setClock(400000);                                          // Increase I2C speed to 400 Khz

  /* ----------------------------------------------------------------
      Initialize INPUT, CHARGING, POWER, and LED Pins
     ----------------------------------------------------------------
  */

  // Battery Charging
  pinMode(22, OUTPUT); // Set PIN 22 for output for battery charging
  digitalWrite(22, LOW); // Set LOW -> 100 mA charge, set HIGH -> 0 mA, leave commented for 50 mA charging)
  //while (Serial) delay(500); // (UNCOMMENT FOR REAL WORLD USE) When plugging in USB to charge, don't turn on rest of device

  // AD8232 PINS
  pinMode(A0, INPUT); // Set A0 pin for INPUT, EOG/EEG analog signal

  // Heartrate Sensor
  pinMode(A1, INPUT); // Set A1 pin for INPUT, Heartrate monitor analog signal

  // Power pin (Delivers power to AD8232 and HR Sensor)
  pinMode(A5, OUTPUT);
  digitalWrite(A5, LOW);                                      // Set A5 pin to ON (Commented: Don't turn on until BLE Connection)

  // Vibration Disc
  pinMode(A4, OUTPUT); // Set A4 pin for OUTPUT for Vibration disc
  digitalWrite(A4, LOW); // Set A4 pin to OFF (Xiao Sense HIGH/LOW is reversed, i.e. active low)


  /* ----------------------------------------------------------------
      Detect USB Charging vs Serial Connection - Detect Start-Up Reason
        - Device will ONLY turn ON if Reset/ON button is pressed,
          or if connected to a USB with a serial connection!
        - Device will turn OFF if connected to USB charger (but will charge)
        - Device will turn OFF if turned on by battery power which is
          automatic after USB connection
        - To create Serial USB connection, open Serial Monitor in Arduino          
     ----------------------------------------------------------------
  */


  // Check if USB Power is for Charging or for Serial Connection (Turn OFF for charging)
  if (powerUSB) {
    unsigned long serialTimeout = millis() + 100000; // Wait 10 Seconds for Serial Connection

    while (!Serial && (millis() < serialTimeout)) {
      delay(150);
      Serial.println("OSSMM - Serial Connection Attempt...");
      digitalWrite(LED_RED, !digitalRead(LED_RED));               // Rapid flip-flop red while checking for Serial Connection
    }

    if (!Serial) {                                                // Final Serial Connection Check

      for (int i = 0; i < 8; i++) {
        digitalWrite(LED_RED, LOW);                             // Turn the RED LED on
        delay(500); // Wait for a half second
        digitalWrite(LED_RED, HIGH); // Turn the RED LED off
        delay(250);
      }

      NRF_POWER->SYSTEMOFF = 1;                                   // USB Power only, go to sleep!
    }
    else {
      Serial.println("OSSMM - Serial Connection Detected");
      digitalWrite(LED_RED, HIGH); // Turn OFF RED LED
      digitalWrite(LED_GREEN, LOW); // Turn ON GREEN LED
      digitalWrite(LED_BLUE, LOW); // Turn ON BLUE LED
    }

  }

  //Check if Start-up was Intentional (Caused by RESET/ON button), otherwise turn OFF!
  if (!resetButtonLaunch){
    for (int i = 0; i < 8; i++) {
        digitalWrite(LED_RED, LOW); // Turn the RED LED on
        delay(500); // Wait for a quarter second
        digitalWrite(LED_RED, HIGH); // Turn the RED LED off
        delay(250);
    }

      NRF_POWER->SYSTEMOFF = 1;                                   // USB Power only, go to sleep!
  }

  
  

  /* ----------------------------------------------------------------
      Initialize Bluetooth Low Energy (BLE) with Security
     ----------------------------------------------------------------
  */
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.configUuid128Count(15);

  Bluefruit.begin();                                            // Start Bluetooth
  Bluefruit.setTxPower(2);                                      // Set Transmit Power, Options: -40, -20, -16, -12, -8, -4, 0, 2, 3, 4, 5, 6, 7, 8
  Bluefruit.autoConnLed(false); // Turn of blue LED to conserve battery
  Bluefruit.setName(DeviceName); // Set Device's named when seen through Bluetooth

  // Configure security for "Just Works" pairing
  // (display, yes_no, keyboard) - for "Just Works" set all to false
  Bluefruit.Security.setIOCaps(false, false, false);
  Bluefruit.Security.setPairPasskeyCallback(NULL);              // No passkey for "Just Works"
  Bluefruit.Security.setPairCompleteCallback(pair_complete_callback);
  Bluefruit.Security.setSecuredCallback(connection_secured_callback);

  Bluefruit.Periph.setConnectCallback(connect_callback);        // Set Callback function for Connection
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback); // Set Callback function for Disconnection
  Bluefruit.Periph.setConnInterval(6, 8);                       // 7.5 - 15 ms set connection interva

  BLEservice.begin(); // Add service to peripheral

  // Configure SLEEP DATA Characteristic with security
  // Properties = Notify, Permission = Encrypted but no MITM
  SleepData.setProperties(CHR_PROPS_NOTIFY);
  SleepData.setPermission(SECMODE_ENC_NO_MITM, SECMODE_NO_ACCESS);  // Encrypted but No MITM protection
  SleepData.setFixedLen(180); // Necessary command, set size to 10 x Measurements (18 bytes)
  SleepData.begin(); // Initialize Characteristic


  // Configure the SLEEP MODULATOR Characteristic with security
  // Properties = Read + Write, Permission = Encrypted but no MITM
  PowerControl.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
  PowerControl.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);  // Encrypted but No MITM protection
  PowerControl.setFixedLen(1);
  PowerControl.begin();
  PowerControl.write8(0x00);  // led = off when started
  PowerControl.setWriteCallback(power_control_callback);
  
  
  // Configure the SLEEP MODULATOR Characteristic with security
  // Properties = Read + Write, Permission = Encrypted but no MITM
  SleepModulator.setProperties(CHR_PROPS_READ | CHR_PROPS_WRITE);
  SleepModulator.setPermission(SECMODE_ENC_NO_MITM, SECMODE_ENC_NO_MITM);  // Encrypted but No MITM protection
  SleepModulator.setFixedLen(1);
  SleepModulator.begin();
  SleepModulator.write8(0x00);  // led = off when started
  SleepModulator.setWriteCallback(sleep_modulator_callback);


  // Advertising configuration
  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);  //BLE only, not classic BT LE
  Bluefruit.Advertising.addTxPower();                                           // Add the power
  Bluefruit.Advertising.addService(BLEservice); // Add the Service UUID

  // Add security flag to advertising data
  Bluefruit.Advertising.addAppearance(BLE_APPEARANCE_GENERIC_WATCH); // Generic watch appearance

  Bluefruit.ScanResponse.addName();  // "Secondary Scan Response Packet" - necessary for BT .setName() to work, and for device to be discoverable by some apps (ie nRFConnect)

  Bluefruit.Advertising.restartOnDisconnect(true); // Think this means if BT disconnects to start advertizing again
  Bluefruit.Advertising.setInterval(100, 244); // in unit of 0.625 ms // (still not sure about this, but these settings work fine)
  Bluefruit.Advertising.setFastTimeout(30); // number of seconds in fast mode (still not sure about this line, what is fast mode vs slow mode?)

  Bluefruit.Advertising.start(0); // 0 = Don't stop advertising after n seconds (still not sure about this line)

  for (int j = 0; j <= 5; j++) {                    // Do 3 low-to-high BLUE LED ramps to show device has completed start-up and ready to work
    for (int i = 255; i >= 0; i = i - 17) {
      analogWrite(LED_BLUE, i); // PWM value from 255 (off) to 0 (full brightness)
      delay(50);
    }
  }
  analogWrite(LED_BLUE, 255);                       // Turn OFF Blue LED
  delay(100); // Additional delay
}

void loop() {
  /*-----------------------------------------------------------------
     Check if BLE is connected, and if initial loop
    -----------------------------------------------------------------
  */
  if (isConnected == true) {  // Check if BLE is connected
    if (initial == true) {    // Check if on connection this is the 1st measurement loop
      nowConnected(); // Signal device connection with LEDs ### NOTE: nowConnected() should be incorporated into the connect_callback, not a separate function
      initial = false; // Change as no longer 'initial' connection phase

      // Initialize timing system at connection start
      lastSampleTime = micros();
    }

    while (isConnected == true) {
      /*-----------------------------------------------------------------
          Collect Measurements using precise timing at set frequency
        -----------------------------------------------------------------
      */
      unsigned long currentTime = micros(); // Determine if it is time to sample again
      if (currentTime - lastSampleTime >= sampling_interval) {

        if (currentTime - lastSampleTime >= 2 * sampling_interval) {
          lastSampleTime = currentTime; // Reset if too far behind
        }
        else {
          lastSampleTime = lastSampleTime + sampling_interval; // Update by sampling_interval to avoid processing delay effects
        }


        // Get IMU Data
        IMU.readAcceleration(accData[0], accData[1], accData[2]); // Collect Accelerometer values
        IMU.readGyroscope(gyroData[0], gyroData[1], gyroData[2]); // Collect Gyroscope values

        // Convert IMU Data (data conversion is for efficient BLE transmission)
        for (int i = 0; i < 3; i++) {
          gyroVals[i] = (uint16_t)(gyroData[i] + 2000); // Convert range from [-2000,+2000] to above zero, int only range of [0, 4000]
          accVals[i] = (uint16_t)((accData[i] + 8.0) * 100); // Convert range from [-8.0,+8.0] to above zero, int only range of [0, 1600]
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

      yield();                                                 // Give other system tasks a chance to run

    }  // End of Transmit-Loop Timer

  } else {                  // if NOT connected, then:
    if (initial == true) {  // Check if 1st loop after device disconnect
      nowDisconnected();
      initial = false;
    }
    delay(100);  // This delay is fine when not connected
  }
}


/* ----------------------------------------------------------------
    BLE Update Function
     - Byte Method requires 18 bytes per sampline
     - [update_num, eog, hr, aX, aY, aZ, gX, gY, gZ]
   ----------------------------------------------------------------
*/
void updateBLE() {

  //Serial.print("Loop number: "); //Serial.println(loop_count);

  if (loop_count >= 10) {
    SleepData.notify(mySleepDataPacket, 180); // Set characteristic message, and notify client
    loop_count = 0;
  } else {
    mySleepDataPacket[(18 * loop_count) + 0] = (char)(update_num & 0xff); // Lower byte of update number (byte string on right)
    mySleepDataPacket[(18 * loop_count) + 1] = (char)((update_num >> 8) & 0xff); // Upper byte of update number (byte string on left)
    mySleepDataPacket[(18 * loop_count) + 2] = (char)(eog & 0xff); // Lower byte of eog (byte string on right)
    mySleepDataPacket[(18 * loop_count) + 3] = (char)((eog >> 8) & 0xff); // Upper byte of eog (byte string on left)
    mySleepDataPacket[(18 * loop_count) + 4] = (char)(hr & 0xff); // Lower byte of hr (byte string on right)
    mySleepDataPacket[(18 * loop_count) + 5] = (char)((hr >> 8) & 0xff); // Upper byte of eogH (byte string on left)
    mySleepDataPacket[(18 * loop_count) + 6] = (char)(accVals[0] & 0xff);
    mySleepDataPacket[(18 * loop_count) + 7] = ((char)((accVals[0] >> 8) & 0xff)); // Upper byte of aX
    mySleepDataPacket[(18 * loop_count) + 8] = ((char)(accVals[1] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 9] = ((char)((accVals[1] >> 8) & 0xff)); // Upper byte of aY
    mySleepDataPacket[(18 * loop_count) + 10] = ((char)(accVals[2] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 11] = ((char)((accVals[2] >> 8) & 0xff)); // Upper byte of aZ
    mySleepDataPacket[(18 * loop_count) + 12] = ((char)(gyroVals[0] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 13] = ((char)((gyroVals[0] >> 8) & 0xff)); // Upper byte of gX
    mySleepDataPacket[(18 * loop_count) + 14] = ((char)(gyroVals[1] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 15] = ((char)((gyroVals[1] >> 8) & 0xff)); // Upper byte of gY
    mySleepDataPacket[(18 * loop_count) + 16] = ((char)(gyroVals[2] & 0xff));
    mySleepDataPacket[(18 * loop_count) + 17] = ((char)((gyroVals[2] >> 8) & 0xff));  // Upper byte of gZ

    update_num++; // Update the 'Update' number
    loop_count++;  // Update look count
  }
}

/* ----------------------------------------------------------------
    Sleep Modulator Callback
     - Function controls Vibration Motor Patten
   ----------------------------------------------------------------
*/

void sleep_modulator_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  Serial.println("Arrived at Sleep Modulator Callback");
  (void)conn_hdl;
  (void)chr;
  (void)len;  // len should be 1

  // data = 0 -> Vibration Motor = OFF
  // data = 1 -> Vibration Motor = ON
  if (data[0]) {
    for (int i = 0; i < 2; i++) {
      for (int j = 0; j < 2; j++) {
        // TURN ON
        digitalWrite(A4, HIGH);
        Serial.println("Vibration Motor ON");

        delay(400);

        // TURN OFF
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
     - Function controls Power Down
   ----------------------------------------------------------------
*/

void power_control_callback(uint16_t conn_hdl, BLECharacteristic* chr, uint8_t* data, uint16_t len) {
  Serial.println("Arrived at Power Control Callback");
  (void)conn_hdl;
  (void)chr;
  (void)len;  // len should be 1

  // data = 2 -> Turn Off Device
  if ( data[0] == 2 ) {
    Serial.println("Received Turn Off command. Shutting down.");

    // Turn off power to external sensors and vibration motor
    digitalWrite(A5, LOW);
    digitalWrite(A4, LOW);

    // Go to deep sleep
    NRF_POWER->SYSTEMOFF = 1;
  }
}
