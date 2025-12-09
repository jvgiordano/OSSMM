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


// lib/src/features/device_scan/screens/find_devices_screen.dart
// Merged ScanResultTile widget into this file.
// Corrected Text widget parameter error.

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp; // Use alias
import 'package:provider/provider.dart';
import 'package:ossmm/src/core/services/bluetooth_service.dart'; // Renamed service

class FindDevicesScreen extends StatefulWidget {
  const FindDevicesScreen({super.key});
  @override
  State<FindDevicesScreen> createState() => _FindDevicesScreenState();
}

class _FindDevicesScreenState extends State<FindDevicesScreen> {
  late OssmmBluetoothService _bluetoothService;

  @override
  void initState() {
    super.initState();
    _bluetoothService = Provider.of<OssmmBluetoothService>(context, listen: false);
    _startScanning();
  }

  @override
  void dispose() {
    try {
      if (_bluetoothService.isScanning) {
        _bluetoothService.stopScan();
      }
    } catch (e) {
      print("Error stopping scan on dispose of FindDevicesScreen: $e");
    }
    super.dispose();
  }

  Future<void> _startScanning() async {
    await _bluetoothService.startScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Devices'),
        actions: [
          Consumer<OssmmBluetoothService>(
            builder: (context, service, child) {
              if (service.isScanning) {
                return TextButton(
                  onPressed: service.stopScan,
                  child: const Text("STOP", style: TextStyle(color: Colors.white)),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<OssmmBluetoothService>(
        builder: (context, service, child) {
          return RefreshIndicator(
            onRefresh: _startScanning,
            child: (service.scanResults.isEmpty && !service.isScanning)
                ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: const Center( // Center widget handles alignment
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      // REMOVED textAlign parameter from Text widget
                      child: Text("No devices found.\nPull down to scan again."),
                    ),
                  ),
                ),
              ),
            )
                : ListView.builder(
              itemCount: service.scanResults.length,
              itemBuilder: (context, index) {
                final result = service.scanResults[index];
                return _ScanResultTile( // Use merged widget
                  result: result,
                  onTap: () {
                    service.stopScan();
                    Navigator.of(context).pop<fbp.BluetoothDevice>(result.device);
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: Consumer<OssmmBluetoothService>(
        builder: (context, service, child) {
          return FloatingActionButton(
            onPressed: service.isScanning ? null : _startScanning,
            backgroundColor: service.isScanning ? Colors.grey : Theme.of(context).colorScheme.primary,
            tooltip: service.isScanning ? 'Scanning...' : 'Start Scan',
            child: service.isScanning
                ? const CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                : const Icon(Icons.search),
          );
        },
      ),
    );
  }
}


// --- Merged ScanResultTile Widget ---
class _ScanResultTile extends StatelessWidget {
  const _ScanResultTile({
    required this.result,
    this.onTap,
  });

  final fbp.ScanResult result;
  final VoidCallback? onTap;

  Widget _buildTitle(BuildContext context) {
    String deviceName = result.device.platformName;
    if (deviceName.isEmpty) { deviceName = result.advertisementData.advName; }
    if (deviceName.isEmpty) { deviceName = "Unknown Device"; }

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text( deviceName, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium,),
        Text( result.device.remoteId.toString(), style: Theme.of(context).textTheme.bodySmall, ),
      ],
    );
  }

  Widget _buildAdvRow(BuildContext context, String title, String value) {
    if (value.isEmpty || value == 'N/A') { return const SizedBox.shrink(); }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$title:', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12.0),
          Expanded( child: Text( value, style: Theme.of(context).textTheme.bodySmall, softWrap: true, ), ),
        ],
      ),
    );
  }

  String _getNiceHexArray(List<int> bytes) {
    if (bytes.isEmpty) return '[]';
    return '[${bytes.map((i) => i.toRadixString(16).padLeft(2, '0')).join(', ')}]' .toUpperCase();
  }

  String _getNiceManufacturerData(Map<int, List<int>> data) {
    if (data.isEmpty) return 'N/A';
    return data.entries.map((entry) => '${entry.key.toRadixString(16).toUpperCase()}: ${_getNiceHexArray(entry.value)}').join('\n');
  }

  String _getNiceServiceData(Map<fbp.Guid, List<int>> data) {
    if (data.isEmpty) return 'N/A';
    return data.entries.map((entry) => '${entry.key.toString().toUpperCase()}: ${_getNiceHexArray(entry.value)}').join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final adv = result.advertisementData;
    final bool isConnectable = adv.connectable;

    return ExpansionTile(
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${result.rssi}dBm', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Icon( isConnectable ? Icons.link : Icons.link_off, size: 18, color: isConnectable ? Colors.green : Colors.grey, ),
        ],
      ),
      title: _buildTitle(context),
      trailing: ElevatedButton(
        onPressed: isConnectable ? onTap : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 12),
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade500,
        ),
        child: const Text('CONNECT'),
      ),
      children: <Widget>[
        _buildAdvRow(context, 'Adv Name', adv.advName),
        _buildAdvRow(context, 'Tx Power', '${adv.txPowerLevel ?? 'N/A'}'),
        _buildAdvRow(context, 'Manufacturer', _getNiceManufacturerData(adv.manufacturerData)),
        _buildAdvRow(context, 'Service UUIDs', adv.serviceUuids.isNotEmpty ? adv.serviceUuids.map((e) => e.toString().toUpperCase()).join(', ') : 'N/A'),
        _buildAdvRow(context, 'Service Data', _getNiceServiceData(adv.serviceData)),
      ],
    );
  }
}
// --- End Merged ScanResultTile Widget ---