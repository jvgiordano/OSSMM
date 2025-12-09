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


// lib/src/core/services/location_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as loc;

class LocationService extends ChangeNotifier {
  final loc.Location _location = loc.Location();
  bool _isLocationEnabled = false;
  Timer? _locationCheckTimer;

  bool get isLocationEnabled => _isLocationEnabled;

  LocationService() {
    _initializeLocationStatus();
    _startLocationMonitoring();
  }

  @override
  void dispose() {
    _locationCheckTimer?.cancel();
    super.dispose();
  }

  // Initialize location service status
  Future<void> _initializeLocationStatus() async {
    await checkLocationStatus();
  }

  // Start periodic monitoring of location service status
  void _startLocationMonitoring() {
    // Check location status every 2 seconds
    _locationCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      checkLocationStatus();
    });
  }

  // Check current location service status
  Future<void> checkLocationStatus() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();

      // Only notify listeners if the status actually changed
      if (_isLocationEnabled != serviceEnabled) {
        _isLocationEnabled = serviceEnabled;
        print("Location service status changed to: $serviceEnabled");
        notifyListeners();
      }
    } catch (e) {
      print("Error checking location status: $e");
      // If there's an error checking, assume it's disabled
      if (_isLocationEnabled) {
        _isLocationEnabled = false;
        notifyListeners();
      }
    }
  }

  // Request to enable location services
  Future<bool> requestLocationService() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        _isLocationEnabled = serviceEnabled;
        print("Location service request result: $serviceEnabled");
        notifyListeners();
        return serviceEnabled;
      }
      return true;
    } catch (e) {
      print("Error requesting location service: $e");
      return false;
    }
  }

  // Force an immediate check (useful for lifecycle events)
  Future<void> forceCheck() async {
    await checkLocationStatus();
  }
}