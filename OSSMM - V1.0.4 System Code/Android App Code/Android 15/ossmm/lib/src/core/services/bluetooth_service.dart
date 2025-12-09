/*
 * OSSMM - Open-Source Sleep Monitor and Modulator
 * Android Application
 *
 * Copyright (C) 2022-2025 Maynooth University
 *
 * Developed by Jonny Giordano at the Hamilton Institute, Maynooth University
 * with funding from Taighde Éireann – Research Ireland (Grant 18/CRT/6049).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */


// lib/src/core/services/bluetooth_service.dart


import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:permission_handler/permission_handler.dart';
import 'package:ossmm/src/core/models/data_sample.dart';
import 'package:ossmm/src/core/utils/csv_writer.dart';
import 'package:ossmm/src/features/home/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Merged BleConstants
class _BleConstants {
  _BleConstants._();

  static final fbp.Guid serviceUuid = fbp.Guid(
    "5aee1a8a-08de-11ed-861d-0242ac120002",
  );

  static final fbp.Guid characteristicUuidData = fbp.Guid(
    "405992d6-0cf2-11ed-861d-0242ac120002",
  );

  static final fbp.Guid characteristicUuidMod = fbp.Guid(
    "1aa00c0d-469a-426b-985c-8299084aed72",
  );

  // Power control characteristic UUID
  static final fbp.Guid characteristicUuidPower = fbp.Guid(
    "018ec2b5-7c82-7773-95e2-a5f374275f0b",
  );

  static const String deviceDirectory = "OSSMM";

  // Add constants for bond status storage
  static const String bondedDevicesKey = "ossmm_bonded_devices";

  // Add constant for CSV deletion preference
  static const String deleteUnencryptedCsvKey = "ossmm_delete_unencrypted_csv";
}

enum DeviceConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

enum DeviceBondState { none, bonding, bonded }

class OssmmBluetoothService with ChangeNotifier {
  // --- State Variables ---
  fbp.BluetoothAdapterState _adapterState = fbp.BluetoothAdapterState.unknown;
  StreamSubscription<fbp.BluetoothAdapterState>? _adapterStateSubscription;
  List<fbp.ScanResult> _scanResults = [];
  StreamSubscription<List<fbp.ScanResult>>? _scanResultsSubscription;
  bool _isScanning = false;
  fbp.BluetoothDevice? _selectedDevice;
  StreamSubscription<fbp.BluetoothConnectionState>? _connectionStateSubscription;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  bool _isConnecting = false;
  fbp.BluetoothCharacteristic? _dataCharacteristic;
  fbp.BluetoothCharacteristic? _modCharacteristic;
  fbp.BluetoothCharacteristic? _powerCharacteristic;
  StreamSubscription<List<int>>? _dataSubscription;
  final CsvWriterUtil _csvWriter = CsvWriterUtil();
  List<DataSample> _currentSamples = [];
  bool _isRecording = false;
  static const int _maxLiveSamples = 7500;

  // --- Bonding State Variables ---
  DeviceBondState _bondState = DeviceBondState.none;
  StreamSubscription? _bondStateSubscription;
  Set<String> _bondedDevices = {};
  bool _autoReconnectToBonded = false;

  // --- CSV Handling Settings ---
  bool _deleteUnencryptedCsv = true;

  // --- Auto-reconnection variables ---
  bool _isAttemptingAutoReconnect = false;
  int _reconnectAttemptCount = 0;
  Timer? _reconnectTimer;
  bool _appInForeground = true;

  // --- AGGRESSIVE Reconnection for Unexpected Disconnects ---
  bool _unexpectedDisconnect = false;
  Timer? _aggressiveReconnectTimer;
  int _aggressiveReconnectAttempts = 0;
  static const int _maxAggressiveReconnectAttempts = 10;
  DateTime? _disconnectTime;
  bool _wasRecordingBeforeDisconnect = false;
  fbp.BluetoothDevice? _lastDisconnectedDevice; // Store device before clearing

  // --- Foreground service callbacks ---
  Function? _onStartRecordingCallback;
  Function? _onStopRecordingCallback;

  // --- Constants based on OBSERVED packet size ---
  static const int _samplesPerPacket = 10;
  static const int _bytesPerSample = 18;
  static const int _expectedPacketSize = _samplesPerPacket * _bytesPerSample;

  // --- Public Getters ---
  fbp.BluetoothAdapterState get adapterState => _adapterState;
  List<fbp.ScanResult> get scanResults => _scanResults;
  bool get isScanning => _isScanning;
  fbp.BluetoothDevice? get selectedDevice => _selectedDevice;
  String get selectedDeviceName =>
      _selectedDevice?.platformName.isNotEmpty ?? false
          ? _selectedDevice!.platformName
          : (_selectedDevice?.remoteId.toString() ?? "None");
  DeviceConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == DeviceConnectionState.connected;
  bool get isConnecting => _isConnecting;
  bool get isRecording => _isRecording;
  String? get csvFilePath => _csvWriter.currentFilePath;
  List<DataSample> get currentRawSamples => List.unmodifiable(_currentSamples);

  // --- Bond State Getters ---
  DeviceBondState get bondState => _bondState;
  bool get isBonded => _bondState == DeviceBondState.bonded;
  bool get isBonding => _bondState == DeviceBondState.bonding;
  Set<String> get bondedDevices => Set.unmodifiable(_bondedDevices);
  bool get autoReconnectToBonded => _autoReconnectToBonded;
  bool get isAttemptingAutoReconnect => _isAttemptingAutoReconnect;
  int get reconnectAttemptCount => _reconnectAttemptCount;

  // --- Aggressive Reconnection Getters ---
  bool get isAggressiveReconnecting => _aggressiveReconnectTimer != null;
  int get aggressiveReconnectAttempts => _aggressiveReconnectAttempts;

  // --- CSV Settings Getter ---
  bool get deleteUnencryptedCsv => _deleteUnencryptedCsv;

  // --- Initialization & Disposal ---
  OssmmBluetoothService() {
    _initialize();
    _loadBondedDevices();
    _loadCsvPreferences();
  }

  void _initialize() {
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = fbp.FlutterBluePlus.adapterState.listen(
          (state) {
        final bool wasOff = _adapterState != fbp.BluetoothAdapterState.on;
        _adapterState = state;

        if (state != fbp.BluetoothAdapterState.on) {
          _handleBluetoothOff();
        } else if (wasOff && state == fbp.BluetoothAdapterState.on) {
          // Bluetooth just turned on
          print("Bluetooth turned ON. Checking for auto-reconnection eligibility...");

          // Delay to allow adapter to fully initialize
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (_autoReconnectToBonded &&
                _bondedDevices.isNotEmpty &&
                _connectionState == DeviceConnectionState.disconnected &&
                !_isConnecting &&
                !_isAttemptingAutoReconnect) {
              print("Auto-reconnection criteria met. Attempting reconnection.");
              _scheduleReconnectionAttempt(immediate: true);
            }
          });
        }

        print("Adapter State Updated: $state");
        notifyListeners();
      },
      onError: (e) => print("Error listening to adapter state: $e"),
    );
  }

  @override
  void dispose() {
    print("Disposing OssmmBluetoothService");
    _adapterStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _dataSubscription?.cancel();
    _bondStateSubscription?.cancel();
    _reconnectTimer?.cancel();
    _aggressiveReconnectTimer?.cancel();
    _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);

    final device = _selectedDevice;
    if (device != null && device.isConnected == true) {
      device.disconnect().catchError((e) {
        print("Error during dispose disconnect: $e");
      });
    }

    super.dispose();
  }

  void _handleBluetoothOff() {
    print("Handling Bluetooth Off event");
    _cancelReconnectionAttempts();
    _cancelAggressiveReconnection();

    if (_isScanning) {
      _stopScanInternal();
    }

    _scanResults = [];

    if (_connectionState != DeviceConnectionState.disconnected) {
      _handleDisconnect(showError: false);
    }

    _connectionState = DeviceConnectionState.disconnected;
    _isConnecting = false;
    _isRecording = false;
    _bondState = DeviceBondState.none;
    _bondStateSubscription?.cancel();
    _bondStateSubscription = null;
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);
    _selectedDevice = null;
    _lastDisconnectedDevice = null;
    _dataCharacteristic = null;
    _modCharacteristic = null;
    _powerCharacteristic = null;
    _currentSamples = [];
    notifyListeners();
  }

  // --- Foreground Service Integration ---
  void setForegroundServiceCallbacks({
    required Function onStartRecording,
    required Function onStopRecording,
  }) {
    _onStartRecordingCallback = onStartRecording;
    _onStopRecordingCallback = onStopRecording;
  }

  // --- Load/Save CSV Preferences ---
  Future<void> _loadCsvPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deleteUnencryptedCsv =
          prefs.getBool(_BleConstants.deleteUnencryptedCsvKey) ?? true;
      print("Loaded CSV deletion preference: $_deleteUnencryptedCsv");
    } catch (e) {
      print("Error loading CSV preferences: $e");
      _deleteUnencryptedCsv = true;
    }
  }

  Future<void> _saveCsvPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _BleConstants.deleteUnencryptedCsvKey,
        _deleteUnencryptedCsv,
      );
      print("Saved CSV deletion preference: $_deleteUnencryptedCsv");
    } catch (e) {
      print("Error saving CSV preferences: $e");
    }
  }

  void setDeleteUnencryptedCsv(bool value) {
    if (_deleteUnencryptedCsv == value) return;
    _deleteUnencryptedCsv = value;
    _saveCsvPreferences();
    notifyListeners();
  }

  // --- App Lifecycle Management ---
  void setAppLifecycleState(bool isInForeground) {
    _appInForeground = isInForeground;

    if (isInForeground &&
        _autoReconnectToBonded &&
        _bondedDevices.isNotEmpty &&
        _connectionState == DeviceConnectionState.disconnected &&
        !_isConnecting &&
        !_isAttemptingAutoReconnect) {
      print("App returned to foreground. Checking for bonded devices...");
      _scheduleReconnectionAttempt(immediate: false);
    } else if (!isInForeground) {
      // App going to background, keep reconnection attempts running
      print("App going to background. Reconnection attempts will continue.");
    }
  }

  // --- Bonding Functions ---
  Future<void> _loadBondedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bondedDevicesList =
          prefs.getStringList(_BleConstants.bondedDevicesKey) ?? [];
      _bondedDevices = bondedDevicesList.toSet();
      print("Loaded ${_bondedDevices.length} bonded devices from storage");

      if (_autoReconnectToBonded &&
          _bondedDevices.isNotEmpty &&
          _adapterState == fbp.BluetoothAdapterState.on &&
          _connectionState == DeviceConnectionState.disconnected) {
        Future.delayed(const Duration(seconds: 2), () {
          _scheduleReconnectionAttempt(immediate: true);
        });
      }
    } catch (e) {
      print("Error loading bonded devices: $e");
      _bondedDevices = {};
    }
  }

  Future<void> _saveBondedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _BleConstants.bondedDevicesKey,
        _bondedDevices.toList(),
      );
      print("Saved ${_bondedDevices.length} bonded devices to storage");
    } catch (e) {
      print("Error saving bonded devices: $e");
    }
  }

  Future<void> _addBondedDevice(String deviceId) async {
    if (!_bondedDevices.contains(deviceId)) {
      _bondedDevices.add(deviceId);
      await _saveBondedDevices();
      notifyListeners();
    }
  }

  Future<void> _removeBondedDevice(String deviceId) async {
    if (_bondedDevices.contains(deviceId)) {
      _bondedDevices.remove(deviceId);
      await _saveBondedDevices();
      notifyListeners();
    }
  }

  Future<void> clearAllBondedDevices() async {
    _bondedDevices.clear();
    await _saveBondedDevices();
    notifyListeners();
  }

  void setAutoReconnectToBonded(bool value) {
    if (_autoReconnectToBonded == value) return;
    _autoReconnectToBonded = value;

    if (value &&
        _bondedDevices.isNotEmpty &&
        _adapterState == fbp.BluetoothAdapterState.on &&
        _connectionState == DeviceConnectionState.disconnected &&
        !_isConnecting &&
        !_isAttemptingAutoReconnect) {
      print("Auto-reconnect turned ON. Scheduling reconnection attempt.");
      _scheduleReconnectionAttempt(immediate: false);
    } else if (!value) {
      _cancelReconnectionAttempts();
    }

    notifyListeners();
  }

  // --- AGGRESSIVE Reconnection Logic with Exponential Backoff ---
  void _startAggressiveReconnection() {
    if (_aggressiveReconnectAttempts >= _maxAggressiveReconnectAttempts) {
      print("Maximum aggressive reconnection attempts reached.");
      _cancelAggressiveReconnection();
      return;
    }

    _aggressiveReconnectAttempts++;

    // Calculate exponential backoff delay: 5s, 10s, 20s, 40s, 60s, 60s...
    int delaySeconds = 5 * math.pow(2, _aggressiveReconnectAttempts - 1).toInt();
    delaySeconds = math.min(delaySeconds, 60); // Cap at 60 seconds

    // Calculate total elapsed time
    if (_disconnectTime != null) {
      final elapsed = DateTime.now().difference(_disconnectTime!);
      print("Time since disconnect: ${elapsed.inSeconds}s");

      // Stop if we've exceeded 10 minutes total
      if (elapsed.inMinutes >= 10) {
        print("Aggressive reconnection timeout (10 minutes) reached.");
        _cancelAggressiveReconnection();
        return;
      }
    }

    print("🔄 Aggressive reconnection attempt $_aggressiveReconnectAttempts of $_maxAggressiveReconnectAttempts in $delaySeconds seconds...");

    _aggressiveReconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_connectionState != DeviceConnectionState.disconnected || _isConnecting) {
        print("Already connected or connecting, cancelling aggressive reconnection.");
        _cancelAggressiveReconnection();
        return;
      }

      // Try to reconnect
      bool success = await _performAggressiveReconnect();

      if (!success && _aggressiveReconnectAttempts < _maxAggressiveReconnectAttempts) {
        // Schedule next attempt
        _startAggressiveReconnection();
      } else if (success) {
        print("✅ Aggressive reconnection successful!");
        _cancelAggressiveReconnection();

        // Resume recording if we were recording before disconnect
        if (_wasRecordingBeforeDisconnect) {
          print("Resuming recording after successful reconnection...");
          Future.delayed(const Duration(milliseconds: 500), () {
            startRecording();
          });
        }
      } else {
        print("❌ Aggressive reconnection failed after all attempts.");
        _cancelAggressiveReconnection();
      }
    });
  }

  Future<bool> _performAggressiveReconnect() async {
    print("🔍 Starting aggressive reconnection scan...");

    // Use the last disconnected device if available
    final targetDevice = _lastDisconnectedDevice ?? _selectedDevice;

    if (_bondedDevices.isEmpty || targetDevice == null) {
      print("No device to reconnect to.");
      return false;
    }

    try {
      // Request BLE permissions
      bool permissionsGranted = await _requestBlePermissions();
      if (!permissionsGranted) {
        print("Cannot reconnect: BLE permissions not granted");
        return false;
      }

      // Scan duration increases with attempts
      int scanDuration = 10 + (_aggressiveReconnectAttempts * 2); // 12, 14, 16... seconds
      scanDuration = math.min(scanDuration, 30); // Cap at 30 seconds

      print("Looking for device: ${targetDevice.platformName} (${targetDevice.remoteId})");
      print("Scanning for $scanDuration seconds...");

      // Start BLE scan
      await _stopScanInternal();
      _isScanning = true;
      _scanResults = [];
      notifyListeners();

      // Start scan with timeout
      await fbp.FlutterBluePlus.startScan(
        timeout: Duration(seconds: scanDuration),
        androidUsesFineLocation: true,
      );

      bool deviceFound = false;
      fbp.BluetoothDevice? foundDevice;

      // Subscribe to scan results
      await for (final results in fbp.FlutterBluePlus.scanResults) {
        for (final result in results) {
          final device = result.device;

          // Look for our previously connected device
          if (device.remoteId == targetDevice.remoteId) {
            print("✅ Found target device: ${device.platformName} (${device.remoteId})");
            deviceFound = true;
            foundDevice = device;
            break;
          }
        }

        if (deviceFound) break;
      }

      // Stop scanning
      await _stopScanInternal();

      // If device found, attempt to connect
      if (deviceFound && foundDevice != null) {
        print("Attempting to connect to device: ${foundDevice.platformName}");
        bool connected = await connectToDevice(foundDevice);

        if (connected) {
          print("✅ Successfully reconnected to device!");
          return true;
        } else {
          print("❌ Failed to connect to device");
        }
      } else {
        print("❌ Device not found in scan");
      }
    } catch (e) {
      print("Error during aggressive reconnection: $e");
      await _stopScanInternal();
    }

    return false;
  }

  void _cancelAggressiveReconnection() {
    _aggressiveReconnectTimer?.cancel();
    _aggressiveReconnectTimer = null;
    _aggressiveReconnectAttempts = 0;
    _unexpectedDisconnect = false;
    _disconnectTime = null;
    _wasRecordingBeforeDisconnect = false;
    _lastDisconnectedDevice = null;

    print("Aggressive reconnection cancelled");
    notifyListeners();
  }

  // --- Standard Auto-Reconnection Logic ---
  void _scheduleReconnectionAttempt({required bool immediate}) {
    _cancelReconnectionAttempts();

    if (immediate) {
      _tryReconnectToBondedDevice();
    } else {
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        _tryReconnectToBondedDevice();
      });
    }
  }

  void cancelReconnectionAttempts() {
    _cancelReconnectionAttempts();
  }

  void _cancelReconnectionAttempts() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_isAttemptingAutoReconnect) {
      _isAttemptingAutoReconnect = false;
      _reconnectAttemptCount = 0;

      if (_isScanning && fbp.FlutterBluePlus.isScanningNow) {
        fbp.FlutterBluePlus.stopScan().catchError((e) {
          print("Error stopping scan during reconnection cancellation: $e");
        });
      }

      notifyListeners();
    }
  }

  Future<bool> triggerBondedDeviceReconnection({
    bool isManualAttempt = true,
  }) async {
    if (_bondedDevices.isEmpty ||
        _isConnecting ||
        _connectionState != DeviceConnectionState.disconnected) {
      return false;
    }

    if (_isAttemptingAutoReconnect) {
      _cancelReconnectionAttempts();
    }

    return await _tryReconnectToBondedDevice(isManualAttempt: isManualAttempt);
  }

  Future<bool> _tryReconnectToBondedDevice({
    bool isManualAttempt = false,
  }) async {
    if (_bondedDevices.isEmpty ||
        _isConnecting ||
        _connectionState != DeviceConnectionState.disconnected ||
        _adapterState != fbp.BluetoothAdapterState.on) {
      return false;
    }

    _isAttemptingAutoReconnect = true;
    _reconnectAttemptCount = 0;
    notifyListeners();

    print("Starting reconnection process to bonded device" +
        (isManualAttempt ? " (manual attempt)" : ""));

    bool reconnectSuccess = false;
    const int maxAttempts = 3;

    try {
      bool permissionsGranted = await _requestBlePermissions();
      if (!permissionsGranted) {
        print("Cannot reconnect: BLE permissions not granted");
        _isAttemptingAutoReconnect = false;
        notifyListeners();
        return false;
      }

      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        if (_connectionState == DeviceConnectionState.connected) {
          reconnectSuccess = true;
          break;
        }

        if (!_isAttemptingAutoReconnect) {
          print("Reconnection process was cancelled.");
          break;
        }

        if (!isManualAttempt && !_autoReconnectToBonded) {
          print("Auto-reconnect disabled. Stopping automatic reconnection attempts.");
          break;
        }

        _reconnectAttemptCount = attempt;
        notifyListeners();

        print("Reconnection attempt $attempt of $maxAttempts");

        int scanDuration = 5 + (attempt * 2);
        print("Scanning for $scanDuration seconds...");

        try {
          await _stopScanInternal();
          _isScanning = true;
          _scanResults = [];
          notifyListeners();

          await fbp.FlutterBluePlus.startScan(
            timeout: Duration(seconds: scanDuration),
            androidUsesFineLocation: true,
          );

          bool deviceFound = false;
          fbp.BluetoothDevice? targetDevice;

          await for (final results in fbp.FlutterBluePlus.scanResults) {
            if (!_isAttemptingAutoReconnect) {
              print("Reconnection process cancelled.");
              break;
            }

            for (final result in results) {
              final device = result.device;
              if (_bondedDevices.contains(device.remoteId.toString())) {
                print("Found bonded device: ${device.platformName} (${device.remoteId})");
                deviceFound = true;
                targetDevice = device;
                break;
              }
            }

            if (deviceFound) break;
          }

          await _stopScanInternal();

          if (deviceFound && targetDevice != null) {
            print("Attempting to connect to bonded device: ${targetDevice.platformName}");
            bool connected = await connectToDevice(targetDevice);

            if (connected) {
              print("Successfully reconnected to bonded device!");
              reconnectSuccess = true;
              break;
            } else {
              print("Failed to connect to bonded device on attempt $attempt");
            }
          } else {
            print("Bonded device not found in scan attempt $attempt");
          }
        } catch (e) {
          print("Error during reconnection scan attempt $attempt: $e");
          await _stopScanInternal();
        }

        if (attempt < maxAttempts) {
          int delaySeconds = 2 * attempt;
          print("Waiting $delaySeconds seconds before next reconnection attempt...");

          bool shouldContinue = await Future.delayed(
            Duration(seconds: delaySeconds),
                () {
              return (isManualAttempt || _autoReconnectToBonded) &&
                  _isAttemptingAutoReconnect &&
                  _connectionState == DeviceConnectionState.disconnected;
            },
          );

          if (!shouldContinue) {
            print("Reconnection process interrupted during delay.");
            break;
          }
        }
      }
    } catch (e) {
      print("Error in reconnection process: $e");
    } finally {
      _isAttemptingAutoReconnect = false;
      _reconnectAttemptCount = 0;
      notifyListeners();
    }

    return reconnectSuccess;
  }

  // --- Permissions ---
  Future<bool> _requestBlePermissions() async {
    print("Requesting Bluetooth Scan/Connect/Location Permissions...");
    Map<Permission, PermissionStatus> statuses = {};

    if (Platform.isAndroid) {
      statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      statuses.forEach((p, s) => print('$p : $s'));

      final bool scanGranted =
          statuses[Permission.bluetoothScan]?.isGranted ?? false;
      final bool connectGranted =
          statuses[Permission.bluetoothConnect]?.isGranted ?? false;
      final bool locationGranted =
          statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      if (!locationGranted) {
        print('Warning: Location permission not granted. BLE scanning might be unreliable.');
      }

      bool allBtGranted = scanGranted && connectGranted;
      if (!allBtGranted) {
        print('Required Bluetooth permissions (Scan & Connect) not granted.');
        return false;
      }

      return true;
    } else if (Platform.isIOS) {
      print("iOS Permissions should be configured in Info.plist");
      return true;
    }

    print("Unsupported platform for BLE permissions or check failed.");
    return false;
  }

  // --- Scanning Logic ---
  Future<void> startScan() async {
    if (_isScanning) {
      print("Scan already in progress.");
      return;
    }

    if (_adapterState != fbp.BluetoothAdapterState.on) {
      print("Cannot scan, Bluetooth is off.");
      return;
    }

    bool blePermissionsGranted = await _requestBlePermissions();
    if (!blePermissionsGranted) {
      print("BLE permissions not granted, cannot start scan.");
      return;
    }

    _isScanning = true;
    _scanResults = [];
    notifyListeners();
    print("Starting BLE scan...");

    try {
      await fbp.FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      _scanResultsSubscription?.cancel();
      _scanResultsSubscription = fbp.FlutterBluePlus.scanResults.listen(
            (results) {
          _scanResults = results;
          notifyListeners();
        },
        onError: (e) {
          print("Scan Error: $e");
          _stopScanInternal();
        },
      );

      await fbp.FlutterBluePlus.isScanning.where((val) => val == false).first;
      print("Scan automatically stopped or was stopped manually.");
      _stopScanInternal();
    } catch (e) {
      print("Error starting scan: $e");
      _stopScanInternal();
    }
  }

  Future<void> stopScan() async {
    await _stopScanInternal();
  }

  Future<void> _stopScanInternal() async {
    if (!fbp.FlutterBluePlus.isScanningNow && !_isScanning) return;

    _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;

    try {
      if (fbp.FlutterBluePlus.isScanningNow) {
        await fbp.FlutterBluePlus.stopScan();
        print("Scan stopped via FlutterBluePlus.");
      }
    } catch (e) {
      print("Error stopping scan via FlutterBluePlus: $e");
    } finally {
      if (_isScanning) {
        _isScanning = false;
        notifyListeners();
        print("Scan state updated to false.");
      }
    }
  }

  // --- Connection Logic with Bond Support ---
  Future<bool> connectToDevice(fbp.BluetoothDevice device) async {
    if (_isConnecting ||
        (_connectionState != DeviceConnectionState.disconnected &&
            _selectedDevice?.remoteId == device.remoteId)) {
      print("Warning: Connection attempt already in progress or already connected/connecting. Request ignored.");
      return isConnected;
    }

    if (_isScanning) {
      await _stopScanInternal();
    }

    if (_adapterState != fbp.BluetoothAdapterState.on) {
      print("Cannot connect, Bluetooth is off.");
      return false;
    }

    _isConnecting = true;
    _connectionState = DeviceConnectionState.connecting;
    _selectedDevice = device;
    _unexpectedDisconnect = false;
    _cancelAggressiveReconnection();
    notifyListeners();

    String deviceId = device.remoteId.toString();
    print("Attempting connection to $selectedDeviceName ($deviceId)");

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _connectionStateSubscription = device.connectionState.listen(
          (state) {
        print("Device $deviceId Connection State Stream Update: $state");

        if (state == fbp.BluetoothConnectionState.disconnected) {
          print("Device $deviceId reported disconnected state via stream.");

          if (_connectionState != DeviceConnectionState.disconnecting &&
              !_isConnecting) {
            // This is an unexpected disconnect
            _unexpectedDisconnect = true;
            _wasRecordingBeforeDisconnect = _isRecording;
            _lastDisconnectedDevice = device; // Store the device before disconnect
            _handleDisconnect(showError: true);
          }
        }
      },
      onError: (e) {
        print("Error in connection state stream for $deviceId: $e");

        if (_connectionState != DeviceConnectionState.disconnecting) {
          _unexpectedDisconnect = true;
          _wasRecordingBeforeDisconnect = _isRecording;
          _lastDisconnectedDevice = device; // Store the device before disconnect
          _handleDisconnect(showError: true);
        }
      },
    );

    try {
      // Check if device is already bonded
      bool isBonded = _bondedDevices.contains(deviceId);

      // Connect with bonding if needed
      await device.connect(
        timeout: const Duration(seconds: 30),
        autoConnect: false,
      );

      // Verify connection before proceeding
      await Future.delayed(const Duration(milliseconds: 500));

      if (!device.isConnected) {
        print("Device not connected after connect() call");
        await _handleDisconnect(showError: true);
        return false;
      }

      // If not bonded, create bond before MTU request
      if (!isBonded && Platform.isAndroid) {
        print("Device not bonded. Creating bond first...");
        try {
          await device.createBond();
          await Future.delayed(const Duration(seconds: 2));
          print("Bond creation initiated");
        } catch (e) {
          print("Bond creation error (may be normal if already bonding): $e");
        }
      }

      // Now attempt the setup
      bool setupOk = await _postConnectionSetup(device);

      if (!setupOk) {
        print("❌ Post-connection setup failed for $deviceId.");
        await _handleDisconnect(showError: true);
        return false;
      }

      _connectionState = DeviceConnectionState.connected;
      _isConnecting = false;
      print("✅ Device $deviceId setup complete and connected.");

      // Update bond state after successful connection
      if (Platform.isAndroid && !_bondedDevices.contains(deviceId)) {
        await _addBondedDevice(deviceId);
      }

      notifyListeners();
      return true;

    } catch (e) {
      print("❌ Error during connect() or setup for device $deviceId: $e");
      await _handleDisconnect(showError: true);
      return false;
    } finally {
      if (_connectionState != DeviceConnectionState.connected &&
          _isConnecting) {
        _isConnecting = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _postConnectionSetup(fbp.BluetoothDevice device) async {
    try {
      print("PostConnect: Waiting 1 second for connection to stabilize...");
      await Future.delayed(const Duration(seconds: 1));
      print("PostConnect: Starting setup for ${device.remoteId}...");

      // Add retry logic for MTU request
      int mtuRetries = 3;
      int mtuSize = 0;

      for (int i = 0; i < mtuRetries; i++) {
        try {
          print("PostConnect: Requesting MTU 184 (attempt ${i + 1})...");
          mtuSize = await device.requestMtu(184);
          print("PostConnect: MTU successfully set to $mtuSize");
          break;
        } catch (e) {
          print("PostConnect: MTU request failed (attempt ${i + 1}): $e");
          if (i == mtuRetries - 1) {
            try {
              print("PostConnect: Trying smaller MTU of 23...");
              mtuSize = await device.requestMtu(23);
              print("PostConnect: MTU set to minimum: $mtuSize");
            } catch (e2) {
              print("PostConnect: Even minimum MTU failed: $e2");
            }
          } else {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));

      try {
        print("PostConnect: Requesting Connection Priority High...");
        await device.requestConnectionPriority(
          connectionPriorityRequest: fbp.ConnectionPriority.high,
        );
      } catch (e) {
        print("PostConnect: Connection priority request failed: $e");
      }

      await Future.delayed(const Duration(milliseconds: 200));

      print("PostConnect: Discovering services...");
      List<fbp.BluetoothService> services = await device.discoverServices();
      print("PostConnect: Found ${services.length} services.");

      await Future.delayed(const Duration(milliseconds: 100));

      _dataCharacteristic = null;
      _modCharacteristic = null;
      _powerCharacteristic = null;

      fbp.BluetoothService? targetService;

      for (var s in services) {
        if (s.uuid == _BleConstants.serviceUuid) {
          targetService = s;
          break;
        }
      }

      if (targetService == null) {
        print("PostConnect: ❌ Error: Required service ${_BleConstants.serviceUuid} not found.");
        return false;
      }

      print("PostConnect: ✅ Found Required Service: ${targetService.uuid}");

      print("PostConnect:   * Iterating characteristics for service ${targetService.uuid}...");
      for (fbp.BluetoothCharacteristic c in targetService.characteristics) {
        print("PostConnect:     - Found characteristic: ${c.uuid}");

        if (c.uuid == _BleConstants.characteristicUuidData) {
          _dataCharacteristic = c;
          print("PostConnect:       -> ✅ Matched Data Characteristic");
        } else if (c.uuid == _BleConstants.characteristicUuidMod) {
          _modCharacteristic = c;
          print("PostConnect:       -> ✅ Matched Modulation Characteristic");
        } else if (c.uuid == _BleConstants.characteristicUuidPower) {
          _powerCharacteristic = c;
          print("PostConnect:       -> ✅ Matched Power Characteristic");
        }
      }

      if (_dataCharacteristic == null) {
        print("PostConnect: ❌ Error: Data characteristic ${_BleConstants.characteristicUuidData} not found.");
        return false;
      }

      if (_modCharacteristic == null) {
        print("PostConnect: ❌ Error: Modulation characteristic ${_BleConstants.characteristicUuidMod} not found.");
        return false;
      }

      if (_powerCharacteristic == null) {
        print("PostConnect: ⚠️ Warning: Power characteristic ${_BleConstants.characteristicUuidPower} not found.");
      }

      if (!_dataCharacteristic!.properties.notify) {
        print("PostConnect: ❌ Error: Data characteristic does NOT support Notify.");
        _dataCharacteristic = null;
        return false;
      }

      if (!_modCharacteristic!.properties.write) {
        print("PostConnect: ⚠️ Warning: Modulation characteristic does NOT support Write.");
      }

      print("PostConnect: ✅ Service discovery and characteristic validation successful.");
      return true;
    } catch (e) {
      print("PostConnect: ❌ Error during post-connection setup: $e");
      print("PostConnect: Stack trace: ${StackTrace.current}");
      return false;
    }
  }

  // --- Setup Bond State Listener ---
  Future<void> _setupBondStateListener(fbp.BluetoothDevice device) async {
    _bondStateSubscription?.cancel();
    _bondStateSubscription = null;

    if (Platform.isAndroid) {
      try {
        if (_bondedDevices.contains(device.remoteId.toString())) {
          _bondState = DeviceBondState.bonded;
          notifyListeners();
        } else {
          _bondState = DeviceBondState.none;
          notifyListeners();
        }

        print("Bond state monitoring set up (using connection status and stored list)");
      } catch (e) {
        print("Error setting up bond state monitoring: $e");
        _bondState = DeviceBondState.none;
        notifyListeners();
      }
    } else {
      _bondState = DeviceBondState.bonded;
      if (_selectedDevice != null) {
        await _addBondedDevice(_selectedDevice!.remoteId.toString());
      }
      notifyListeners();
    }
  }

  Future<bool> createBond() async {
    if (_selectedDevice == null || !isConnected) {
      print("Cannot create bond: No device connected");
      return false;
    }

    if (_bondState == DeviceBondState.bonded) {
      print("Device is already bonded");
      return true;
    }

    try {
      print("Initiating bond with ${_selectedDevice!.platformName}");
      _bondState = DeviceBondState.bonding;
      notifyListeners();

      if (Platform.isAndroid) {
        try {
          await _selectedDevice!.createBond();
          print("Bond creation completed without exceptions");
          _bondState = DeviceBondState.bonded;
          notifyListeners();

          if (_selectedDevice != null) {
            await _addBondedDevice(_selectedDevice!.remoteId.toString());
          }
          return true;
        } catch (e) {
          print("Error in createBond method: $e");
          _bondState = DeviceBondState.none;
          notifyListeners();
          return false;
        }
      } else {
        _bondState = DeviceBondState.bonded;
        notifyListeners();
        await _addBondedDevice(_selectedDevice!.remoteId.toString());
        return true;
      }
    } catch (e) {
      print("Error creating bond: $e");
      _bondState = DeviceBondState.none;
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeBond() async {
    if (_selectedDevice == null) {
      print("Cannot remove bond: No device selected");
      return false;
    }

    try {
      final deviceId = _selectedDevice!.remoteId.toString();

      if (Platform.isAndroid) {
        print("Removing bond with $deviceId");
        try {
          await _selectedDevice!.removeBond();
          await _removeBondedDevice(deviceId);
          _bondState = DeviceBondState.none;
          notifyListeners();
          return true;
        } catch (e) {
          print("Error in removeBond method: $e");
          return false;
        }
      } else {
        await _removeBondedDevice(deviceId);
        _bondState = DeviceBondState.none;
        notifyListeners();
        return true;
      }
    } catch (e) {
      print("Error removing bond: $e");
      return false;
    }
  }

  // --- Disconnect and Turn Off Device ---
  Future<void> disconnectAndTurnOffDevice({
    bool showError = false,
    bool? saveData,
  }) async {
    final deviceToDisconnect = _selectedDevice;

    if (deviceToDisconnect == null ||
        _connectionState == DeviceConnectionState.disconnected) {
      print("Not connected or no device selected.");
      _isConnecting = false;

      if (_connectionState != DeviceConnectionState.disconnected) {
        _connectionState = DeviceConnectionState.disconnected;
        notifyListeners();
      }
      return;
    }

    print("Disconnecting & Turning Off ${deviceToDisconnect.platformName}...");

    if (_isConnecting) _isConnecting = false;

    _cancelReconnectionAttempts();
    _cancelAggressiveReconnection();

    final wasRecording = _isRecording;
    _connectionState = DeviceConnectionState.disconnecting;
    notifyListeners();

    // CRITICAL: Send MCU shutdown command first
    if (_powerCharacteristic != null && _powerCharacteristic!.properties.write) {
      try {
        print("Sending MCU shutdown command (0x02) to power characteristic...");

        await _powerCharacteristic!.write(
          [0x02],
          withoutResponse: _powerCharacteristic!.properties.writeWithoutResponse,
        );

        print("MCU shutdown command sent successfully.");
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print("Error writing MCU shutdown command to power characteristic: $e");
      }
    } else {
      print("Error: Cannot send shutdown command. Power characteristic is missing or does not support write.");
    }

    if (wasRecording) {
      await stopRecording(saveData: saveData ?? true);
    } else {
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      if (_csvWriter.isInitialized) {
        await _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);
      }
    }

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    await _bondStateSubscription?.cancel();
    _bondStateSubscription = null;

    try {
      print("Calling platform disconnect for ${deviceToDisconnect.remoteId}...");

      if (deviceToDisconnect.isConnected == true) {
        await deviceToDisconnect.disconnect();
        print("Platform disconnect completed.");
      } else {
        print("Device reported as not connected before platform disconnect call.");
      }
    } catch (e) {
      print("Error during disconnect call: $e");
      _handleDisconnect(showError: showError || true);
    } finally {
      if (_connectionState != DeviceConnectionState.disconnected) {
        print("Manually ensuring disconnected state after disconnect attempt.");
        _handleDisconnect(showError: showError);
      }
    }
  }

  Future<void> _handleDisconnect({required bool showError}) async {
    if (_connectionState == DeviceConnectionState.disconnected &&
        !_isConnecting)
      return;

    print("Executing disconnection cleanup logic...");

    // Store device info BEFORE clearing
    final deviceId = _selectedDevice?.remoteId.toString() ?? "Unknown";
    final disconnectedDevice = _selectedDevice; // Store the device reference
    final wasRecording = _isRecording;

    _connectionState = DeviceConnectionState.disconnected;
    _isRecording = false;
    _isConnecting = false;

    await _bondStateSubscription?.cancel();
    _bondStateSubscription = null;

    if (wasRecording) {
      print("Stopping recording tasks due to disconnect...");
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      await _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);

      // Stop foreground service
      _onStopRecordingCallback?.call();

      if (!showError) {
        print("Data possibly saved (check CSV writer close log).");
      } else {
        print("Data saving aborted due to error. Check file state.");
      }
    } else {
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      if (_csvWriter.isInitialized) {
        await _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);
      }
    }

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _dataCharacteristic = null;
    _modCharacteristic = null;
    _powerCharacteristic = null;
    _currentSamples = [];
    _selectedDevice = null; // Clear selected device AFTER storing it

    print("Cleanup after disconnect for device $deviceId complete.");

    if (showError) {
      print("Disconnect reason: Error or unexpected device disconnection.");
    }

    // AGGRESSIVE reconnection for unexpected disconnects
    // Use the stored device reference
    if (_unexpectedDisconnect &&
        disconnectedDevice != null &&
        _adapterState == fbp.BluetoothAdapterState.on &&
        showError) {
      print("🚨 Unexpected disconnect detected. Starting AGGRESSIVE reconnection...");
      _disconnectTime = DateTime.now();
      _wasRecordingBeforeDisconnect = wasRecording;
      _lastDisconnectedDevice = disconnectedDevice; // Store the device for reconnection
      _startAggressiveReconnection();
    }
    // Standard auto-reconnect logic
    else if (_autoReconnectToBonded &&
        _bondedDevices.isNotEmpty &&
        _adapterState == fbp.BluetoothAdapterState.on &&
        !_isAttemptingAutoReconnect &&
        showError) {
      print("Unexpected disconnect detected. Scheduling standard reconnection attempt.");
      _scheduleReconnectionAttempt(immediate: false);
    }

    notifyListeners();
  }

  // --- Show Data Access Password ---
  Future<void> showDataAccessPassword(BuildContext context) async {
    await _csvWriter.showDataAccessPassword(context);
  }

  // --- Recording & Data Handling ---
  Future<bool> startRecording() async {
    if (!isConnected ||
        _selectedDevice == null ||
        _dataCharacteristic == null) {
      print("Cannot start recording: Not connected or data characteristic not found.");
      return false;
    }

    if (_isRecording) {
      print("Recording is already in progress.");
      return true;
    }

    print("Attempting to start recording...");

    bool csvReady = await _csvWriter.initialize();

    if (!csvReady) {
      print("Failed to initialize CSV writer. Check permissions and storage path.");
      return false;
    }

    _currentSamples = [];

    try {
      if (!_dataCharacteristic!.isNotifying) {
        await _dataCharacteristic!.setNotifyValue(true);
        print("Subscribed to data characteristic notifications.");
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        print("Data characteristic notifications already enabled.");
      }

      await _dataSubscription?.cancel();

      _dataSubscription = _dataCharacteristic!.onValueReceived.listen(
            (data) {
          if (data.length == _expectedPacketSize) {
            bool samplesAddedForPlotting = false;

            for (int i = 0; i < _samplesPerPacket; i++) {
              int offset = i * _bytesPerSample;

              try {
                final sample = DataSample(
                  transNum: data[offset + 0] + (256 * data[offset + 1]),
                  eog: data[offset + 2] + (256 * data[offset + 3]),
                  hr: data[offset + 4] + (256 * data[offset + 5]),
                  accX: data[offset + 6] + (256 * data[offset + 7]),
                  accY: data[offset + 8] + (256 * data[offset + 9]),
                  accZ: data[offset + 10] + (256 * data[offset + 11]),
                  gyroX: data[offset + 12] + (256 * data[offset + 13]),
                  gyroY: data[offset + 14] + (256 * data[offset + 15]),
                  gyroZ: data[offset + 16] + (256 * data[offset + 17]),
                  timestamp: DateTime.now(),
                );

                _csvWriter.appendSample(sample);

                if (i == 0) {
                  _currentSamples.add(sample);
                  samplesAddedForPlotting = true;
                }
              } catch (e) {
                print("Error parsing sample $i from packet at offset $offset: $e");
                break;
              }
            }

            if (samplesAddedForPlotting &&
                _currentSamples.length > _maxLiveSamples) {
              _currentSamples.removeRange(
                0,
                _currentSamples.length - _maxLiveSamples,
              );
            }

            if (samplesAddedForPlotting) {
              notifyListeners();
            }
          } else {
            print("Warning: Received data packet with unexpected size. Expected $_expectedPacketSize, got ${data.length}. Ignoring packet.");
          }
        },
        onError: (error) {
          print("Error in data subscription stream: $error");
          _unexpectedDisconnect = true;
          _wasRecordingBeforeDisconnect = true;
          _lastDisconnectedDevice = _selectedDevice;
          _handleDisconnect(showError: true);
        },
        onDone: () {
          print("Data subscription stream closed by peripheral.");
          _unexpectedDisconnect = true;
          _wasRecordingBeforeDisconnect = true;
          _lastDisconnectedDevice = _selectedDevice;
          _handleDisconnect(showError: false);
        },
        cancelOnError: true,
      );

      _isRecording = true;

      // Start foreground service
      _onStartRecordingCallback?.call();

      print("✅ Recording started. Saving data to: ${csvFilePath ?? 'N/A'}");
      notifyListeners();
      return true;
    } catch (e, stacktrace) {
      print("❌ Error starting recording or setting notifications: $e");
      print(stacktrace);
      _isRecording = false;
      await _dataSubscription?.cancel();
      _dataSubscription = null;
      await _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);

      if (_dataCharacteristic != null &&
          _dataCharacteristic!.properties.notify) {
        await _dataCharacteristic?.setNotifyValue(false).catchError((err) {
          print("Error disabling notifications after failed start: $err");
        });
      }

      notifyListeners();
      return false;
    }
  }

  Future<void> stopRecording({required bool saveData}) async {
    if (!_isRecording) return;

    print("Stopping recording...");

    final wasRecording = _isRecording;
    _isRecording = false;

    // Stop foreground service
    _onStopRecordingCallback?.call();

    notifyListeners();

    await _dataSubscription?.cancel();
    _dataSubscription = null;

    if (_dataCharacteristic != null && _selectedDevice?.isConnected == true) {
      try {
        if (_dataCharacteristic!.properties.notify &&
            _dataCharacteristic!.isNotifying) {
          print("Unsubscribing from data characteristic...");
          await _dataCharacteristic!.setNotifyValue(false);
          print("Unsubscribed successfully.");
        }
      } catch (e) {
        print("Error unsubscribing from data characteristic: $e");
      }
    } else {
      print("Not connected or characteristic invalid, cannot unsubscribe.");
    }

    if (wasRecording) {
      if (saveData) {
        final savedPath = _csvWriter.currentFilePath;
        await _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);
        print("Recording stopped. Data saved to: ${savedPath ?? 'path not available'}");

        if (navigatorKey.currentContext != null) {
          await _csvWriter.showDataAccessPassword(navigatorKey.currentContext!);
        }
      } else {
        await _csvWriter.deleteCurrentFile();
        print("Recording stopped. Data discarded.");
      }
    } else if (_csvWriter.isInitialized) {
      await _csvWriter.close(deleteUnencryptedCsv: _deleteUnencryptedCsv);
      print("CSV writer closed unexpectedly.");
    }
  }

  // --- Modulation Logic ---
  Future<void> testModulate() async {
    if (!isConnected || _modCharacteristic == null) {
      print("Cannot modulate: Not connected or mod char not found.");
      return;
    }

    if (!_modCharacteristic!.properties.write) {
      print("Modulation characteristic does not support write.");
      return;
    }

    try {
      print("Sending Modulation command (0x01)...");

      await _modCharacteristic!.write(
        [0x01],
        withoutResponse: _modCharacteristic!.properties.writeWithoutResponse,
      );

      print("Modulation command sent.");
    } catch (e) {
      print("Error writing modulation command: $e");
    }
  }

  // --- Helpers for Plotting ---
  Iterable<DataSample> getRawSamplesInWindow(Duration duration) {
    if (_currentSamples.isEmpty) return [];

    if (duration.isNegative || duration == Duration.zero) return [];

    final DateTime cutoffTime = DateTime.now().subtract(duration);

    if (_currentSamples.isNotEmpty &&
        !_currentSamples.first.timestamp.isBefore(cutoffTime)) {
      return List.unmodifiable(_currentSamples);
    }

    int startIndex = _currentSamples.indexWhere(
          (sample) => !sample.timestamp.isBefore(cutoffTime),
    );

    if (startIndex == -1) return [];

    return _currentSamples.getRange(startIndex, _currentSamples.length);
  }

  List<DataSample> getDownsampledSamples(Duration duration) {
    final List<DataSample> relevantSamples =
    getRawSamplesInWindow(duration).toList();

    if (relevantSamples.isEmpty) return [];

    return relevantSamples;
  }
}