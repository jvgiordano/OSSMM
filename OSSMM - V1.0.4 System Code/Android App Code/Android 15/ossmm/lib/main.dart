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

// lib/main.dart

import 'dart:io';
import 'dart:convert';
import 'dart:async'; // <-- needed for Timer

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:location/location.dart' as loc;

// Adjust these import paths if your project structure differs.
import 'package:ossmm/src/core/services/bluetooth_service.dart';
import 'package:ossmm/src/core/services/location_service.dart';
import 'package:ossmm/src/features/home/screens/home_screen.dart';
import 'package:ossmm/src/features/system_requirements/screens/system_requirements_screen.dart';

// Keep navigator key if you use it elsewhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ===== Foreground Task setup (v9.x) =====

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_OssmmTaskHandler());
}

class _OssmmTaskHandler extends TaskHandler {
  DateTime? _startedAt;

  @override
  Future<void> onStart(DateTime ts, TaskStarter starter) async {
    _startedAt = ts;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'OSSMM Recording Active',
      notificationText: 'Recording sensor data...',
    );
  }

  @override
  void onRepeatEvent(DateTime ts) {
    if (_startedAt == null) return;
    final secs = ts.difference(_startedAt!).inSeconds;
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');

    FlutterForegroundTask.updateService(
      notificationText: 'Recording • $mm:$ss',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // Optional cleanup; keeping it empty is fine.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();
  _initializeForegroundService();

  fbp.FlutterBluePlus.setLogLevel(fbp.LogLevel.info, color: true);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OssmmBluetoothService()),
        ChangeNotifierProvider(create: (_) => LocationService()),
      ],
      child: const _OssmmApp(),
    ),
  );
}

void _initializeForegroundService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'ossmm_recording_service',
      channelName: 'OSSMM Recording Service',
      channelDescription: 'Maintains BLE connection and records sensor data',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  if (Platform.isAndroid) {
    () async {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }();
  }
}

// ===== App widget =====

class _OssmmApp extends StatefulWidget {
  const _OssmmApp({Key? key}) : super(key: key);

  @override
  State<_OssmmApp> createState() => _OssmmAppState();
}

class _OssmmAppState extends State<_OssmmApp> with WidgetsBindingObserver {
  late LocationService _locationService;
  late OssmmBluetoothService _bluetoothService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _locationService = context.read<LocationService>();
    _bluetoothService = context.read<OssmmBluetoothService>();

    _bluetoothService.setForegroundServiceCallbacks(
      onStartRecording: _startForegroundService,
      onStopRecording: _stopForegroundService,
    );

    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    try {
      final map = (data is String)
          ? jsonDecode(data) as Map<String, dynamic>
          : (data as Map).cast<String, dynamic>();

      final action = map['action'] as String?;
      if (action == 'buttonPressed' && map['buttonId'] == 'stop') {
        _bluetoothService.stopRecording(saveData: true);
      }
    } catch (_) {}
  }

  Future<void> _startForegroundService() async {
    try {
      await WakelockPlus.enable();

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'OSSMM Recording Active',
          notificationText: 'Recording sensor data...',
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceTypes: const [
            ForegroundServiceTypes.connectedDevice,
            ForegroundServiceTypes.dataSync,
          ],
          serviceId: 256,
          notificationTitle: 'OSSMM Recording Active',
          notificationText: 'Recording started — Tap to open app',
          notificationButtons: [
            NotificationButton(id: 'stop', text: 'Stop Recording'),
          ],
          callback: startCallback,
        );
      }
    } catch (e) {
      debugPrint('[Main] Exception starting FGS: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await WakelockPlus.disable();
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[Main] Exception stopping FGS: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _locationService.forceCheck();
      _bluetoothService.setAppLifecycleState(true);
    } else if (state == AppLifecycleState.paused) {
      _bluetoothService.setAppLifecycleState(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // THEME UNCHANGED: classic Material 2 look.
    return WithForegroundTask(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'OSSMM App',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: const _RootShell(), // <- pure conditional render (no nav stack)
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

// ===== Pure conditional shell (no navigation) =====
/// Root shell that renders exactly two screens:
/// - HomeScreen when Bluetooth ON && Location ON
/// - SystemRequirementsScreen otherwise
/// No navigation stack tricks.
class _RootShell extends StatefulWidget {
  const _RootShell({Key? key}) : super(key: key);

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> with WidgetsBindingObserver {
  final loc.Location _locPlugin = loc.Location();
  bool _pluginLocationOn = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLocation();
    // Poll service state so toggling Location is detected reliably
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refreshLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshLocation();
    }
  }

  Future<void> _refreshLocation() async {
    try {
      final on = await _locPlugin.serviceEnabled(); // read-only; no prompts
      if (!mounted) return;
      if (on != _pluginLocationOn) {
        setState(() => _pluginLocationOn = on);
      }
    } catch (_) {
      // If the plugin throws for any reason, we leave the old value.
    }
  }

  @override
  Widget build(BuildContext context) {
    // We rely on your Bluetooth provider for adapter state.
    return Consumer<OssmmBluetoothService>(
      builder: (context, bt, _) {
        final bluetoothOn = bt.adapterState == fbp.BluetoothAdapterState.on;

        // EXACTLY TWO STATES:
        if (bluetoothOn && _pluginLocationOn) {
          return const HomeScreen(); // main page
        } else {
          return const SystemRequirementsScreen(); // requirements page
        }
      },
    );
  }
}
