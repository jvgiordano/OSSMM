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


// lib/src/features/system_requirements/screens/system_requirements_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;
import 'package:provider/provider.dart';
import 'package:ossmm/src/core/services/location_service.dart';
import 'package:ossmm/src/core/services/bluetooth_service.dart';

class SystemRequirementsScreen extends StatelessWidget {
  const SystemRequirementsScreen({super.key});

  String _getBluetoothStateText(fbp.BluetoothAdapterState? state) {
    switch (state) {
      case fbp.BluetoothAdapterState.unknown:
        return 'Unknown';
      case fbp.BluetoothAdapterState.unavailable:
        return 'Unavailable';
      case fbp.BluetoothAdapterState.unauthorized:
        return 'Unauthorized';
      case fbp.BluetoothAdapterState.turningOn:
        return 'Turning On';
      case fbp.BluetoothAdapterState.on:
        return 'On';
      case fbp.BluetoothAdapterState.turningOff:
        return 'Turning Off';
      case fbp.BluetoothAdapterState.off:
        return 'Off';
      default:
        return 'Not Available';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to both services directly using Consumer2
    return Consumer2<OssmmBluetoothService, LocationService>(
      builder: (context, bluetoothService, locationService, child) {
        final bluetoothState = bluetoothService.adapterState;
        final locationEnabled = locationService.isLocationEnabled;

        final bluetoothStateText = _getBluetoothStateText(bluetoothState);
        final locationStateText = locationEnabled ? 'On' : 'Off';

        // Determine if all requirements are met
        bool allRequirementsMet = bluetoothState == fbp.BluetoothAdapterState.on &&
            locationEnabled;

        return WillPopScope(
          // Prevent users from backing out of this screen
          onWillPop: () async => false,
          child: Scaffold(
            backgroundColor: allRequirementsMet ? Colors.green : Theme.of(context).primaryColor,
            body: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Welcome to OSSMM',
                        style: Theme.of(context).primaryTextTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),

                      // Show different icon based on requirements status
                      Icon(
                        allRequirementsMet ? Icons.check_circle : Icons.warning,
                        size: 150.0,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 20),

                      // System requirements header
                      Text(
                        allRequirementsMet ? 'All Requirements Met' : 'System Requirements',
                        style: Theme.of(context).primaryTextTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // Important notice
                      if (!allRequirementsMet) ...[
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          margin: const EdgeInsets.only(bottom: 20.0),
                          decoration: BoxDecoration(
                            color: Colors.yellow.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.yellow, width: 1),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info, color: Colors.yellow, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Both Bluetooth and Location must be enabled for the app to function properly',
                                  style: TextStyle(
                                    color: Colors.yellow[100],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Bluetooth Section
                      _buildServiceSection(
                        context: context,
                        title: 'Bluetooth',
                        isEnabled: bluetoothState == fbp.BluetoothAdapterState.on,
                        statusText: 'Bluetooth is $bluetoothStateText',
                        icon: bluetoothState == fbp.BluetoothAdapterState.on
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        showButton: bluetoothState == fbp.BluetoothAdapterState.off,
                        buttonText: 'TURN ON BLUETOOTH',
                        onButtonPressed: () async {
                          try {
                            if (Platform.isAndroid) {
                              await fbp.FlutterBluePlus.turnOn();
                            } else if (Platform.isIOS) {
                              // Show prompt for iOS user
                              await showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text("Turn On Bluetooth"),
                                  content: const Text(
                                      "Please enable Bluetooth in your device's Control Center or Settings."
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: Navigator.of(context).pop,
                                      child: const Text("OK"),
                                    ),
                                  ],
                                ),
                              );
                            }
                          } catch (e) {
                            print("Error requesting Bluetooth turn on: $e");
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Could not request Bluetooth: $e")),
                              );
                            }
                          }
                        },
                      ),

                      const SizedBox(height: 16),

                      // Location Section
                      _buildServiceSection(
                        context: context,
                        title: 'Location',
                        isEnabled: locationEnabled,
                        statusText: 'Location is $locationStateText',
                        icon: locationEnabled
                            ? Icons.location_on
                            : Icons.location_off,
                        showButton: !locationEnabled,
                        buttonText: 'TURN ON LOCATION',
                        onButtonPressed: () async {
                          bool success = await locationService.requestLocationService();
                          if (!success && context.mounted) {
                            // Show additional guidance if location can't be enabled
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text("Location Required"),
                                content: const Text(
                                    "This app requires location services to scan for Bluetooth devices. "
                                        "If the location service cannot be enabled directly, please enable it in your device settings."
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: Navigator.of(context).pop,
                                    child: const Text("OK"),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      ),

                      // Explanation why location is needed
                      if (!locationEnabled) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.help_outline, color: Colors.blue[300], size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Location is required for Bluetooth scanning on Android',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildServiceSection({
    required BuildContext context,
    required String title,
    required bool isEnabled,
    required String statusText,
    required IconData icon,
    required bool showButton,
    required String buttonText,
    required VoidCallback onButtonPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? Colors.green
              : Colors.red.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 30.0,
                color: isEnabled
                    ? Colors.green[300]
                    : Colors.red[300],
              ),
              const SizedBox(width: 10),
              Text(
                statusText,
                style: Theme.of(context).primaryTextTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          if (showButton) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: Icon(icon),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Theme.of(context).primaryColor,
              ),
              onPressed: onButtonPressed,
              label: Text(buttonText),
            ),
          ],
        ],
      ),
    );
  }
}