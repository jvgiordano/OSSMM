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


// lib/src/core/utils/app_lifecycle_observer.dart

import 'package:flutter/material.dart';
import 'package:ossmm/src/core/services/bluetooth_service.dart';

/// AppLifecycleObserver is a class that observes app lifecycle changes
/// and notifies the Bluetooth service when the app enters or exits the foreground.
class AppLifecycleObserver extends WidgetsBindingObserver {
  final OssmmBluetoothService bluetoothService;
  bool _wasInForeground = true;
  bool _disposed = false;

  AppLifecycleObserver(this.bluetoothService) {
    WidgetsBinding.instance.addObserver(this);

    // Initialize with current state
    bluetoothService.setAppLifecycleState(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;

    try {
      switch (state) {
        case AppLifecycleState.resumed:
        // App in foreground
          if (!_wasInForeground) {
            print('App resumed - now in foreground');
            bluetoothService.setAppLifecycleState(true);
            _wasInForeground = true;
          }
          break;

        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
        // App in background or being closed
          if (_wasInForeground) {
            print('App paused/inactive/detached - now in background');
            bluetoothService.setAppLifecycleState(false);
            _wasInForeground = false;
          }
          break;
      }
    } catch (e) {
      print('Error in lifecycle state change: $e');
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }
}