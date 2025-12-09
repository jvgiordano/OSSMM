// lib/src/features/home/screens/home_screen.dart



import 'package:flutter/material.dart';

import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'package:provider/provider.dart';

import 'package:ossmm/src/core/services/bluetooth_service.dart';

import 'package:ossmm/src/core/services/location_service.dart';

import 'package:ossmm/src/features/data_display/widgets/live_data_chart.dart';

import 'package:ossmm/src/features/device_scan/screens/find_devices_screen.dart';

import 'package:ossmm/src/features/system_requirements/screens/system_requirements_screen.dart';

import 'package:ossmm/src/core/utils/app_lifecycle_observer.dart';

import 'dart:async';

import 'package:ossmm/src/core/models/data_sample.dart';



// Add this for global context access

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();



class HomeScreen extends StatefulWidget {

const HomeScreen({super.key});

@override

State<HomeScreen> createState() => _HomeScreenState();

}



class _HomeScreenState extends State<HomeScreen> {

// Local UI state

bool _modulationEnabled = false;

bool _startStopWithConnection = true; // Default to true



// Store the service instance for easy access in listeners

late OssmmBluetoothService _bluetoothService;

late LocationService _locationService; // Store location service reference



// Add this variable for lifecycle management

late AppLifecycleObserver _lifecycleObserver;



// Added state variable to track if device was intentionally turned off

bool _deviceIntentionallyTurnedOff = false;

// Add state variable to track manual reconnection attempts

bool _isPerformingManualReconnect = false;



// *** ADDED: Track previous connection state for auto-start logic ***

DeviceConnectionState? _previousConnectionState;



@override

void initState() {

super.initState();

// Get service instances (don't listen here, use Consumer/watch elsewhere)

_bluetoothService = Provider.of<OssmmBluetoothService>(context, listen: false);

_locationService = Provider.of<LocationService>(context, listen: false);



// *** ADDED: Initialize previous connection state ***

_previousConnectionState = _bluetoothService.connectionState;



// Schedule state modifications for after the current build completes

// This prevents the "setState during build" error

Future.microtask(() {

// Set deleteUnencryptedCsv to true by default

_bluetoothService.setDeleteUnencryptedCsv(false);



// Ensure Auto-Reconnect in service defaults to false on init

_bluetoothService.setAutoReconnectToBonded(false);

});



// Add listener to react to service state changes

_bluetoothService.addListener(_handleServiceStateChange);



// Initialize app lifecycle observer

_lifecycleObserver = AppLifecycleObserver(_bluetoothService);



// Reset the turn-off flag initially

_deviceIntentionallyTurnedOff = false;



// Monitor location service status

_locationService.addListener(_checkSystemRequirements);

}



@override

void dispose() {

// Remove listeners BEFORE anything else

_bluetoothService.removeListener(_handleServiceStateChange);

_locationService.removeListener(_checkSystemRequirements);



// Dispose lifecycle observer

_lifecycleObserver.dispose();

super.dispose();

}



// Add this new method to handle system requirements checking

void _checkSystemRequirements() {

// Check if widget is still mounted

if (!mounted) return;



bool bluetoothEnabled = _bluetoothService.adapterState == fbp.BluetoothAdapterState.on;

bool locationEnabled = _locationService.isLocationEnabled;



// If either requirement is not met, navigate back to system requirements screen

if (!bluetoothEnabled || !locationEnabled) {

WidgetsBinding.instance.addPostFrameCallback((_) {

if (mounted) {

Navigator.of(context).pushAndRemoveUntil(

MaterialPageRoute(

builder: (_) => const SystemRequirementsScreen(),

),

(route) => false,

);

}

});

}

}



// Listener callback for service state changes

void _handleServiceStateChange() {

// Check if widget is still mounted

if (!mounted) return;



// Get the current state *before* any potential setState calls

final currentState = _bluetoothService.connectionState;



// Reset the intentional turn-off flag ONLY when device connects.

if (currentState == DeviceConnectionState.connected) {

if (_deviceIntentionallyTurnedOff) { // Only update state if it changes

// Use WidgetsBinding to ensure setState is called safely after build

WidgetsBinding.instance.addPostFrameCallback((_) {

if (mounted) {

setState(() {

_deviceIntentionallyTurnedOff = false;

});

}

});

}

}



// --- Handle Auto-Start Recording (if toggle is enabled) ---

// *** MODIFIED: Check for transition TO connected state ***

if (currentState == DeviceConnectionState.connected && // Check NEW state is connected

_previousConnectionState != DeviceConnectionState.connected && // Ensure previous state was NOT connected

_startStopWithConnection && // Check toggle is enabled AT THE TIME of connection

!_bluetoothService.isRecording) { // Check not already recording

print("Auto-start condition met (transitioned to connected with toggle enabled). Attempting to start recording...");

// Use a short delay to ensure state propagation before starting recording

Future.delayed(const Duration(milliseconds: 100), () {

// Check connection state again inside the delayed future

if (mounted && _bluetoothService.isConnected && !_bluetoothService.isRecording) { // Check mounted

_bluetoothService.startRecording().then((success) {

if (!success && mounted) { // Check mounted again

_showErrorDialog(context, "Auto-Recording Failed", "Could not automatically start recording.");

} else if (success) {

print("Auto-recording started successfully.");

}

});

} else {

print("Conditions for auto-start no longer met after delay (disconnected or already recording).");

}

});

}

// Note: Auto-stopping based on disconnect is handled implicitly by the service's _handleDisconnect logic.



// Update previous state *after* processing the current change

_previousConnectionState = currentState;



// Trigger rebuild if connection state changes to update button/toggle states

// Use WidgetsBinding to ensure setState is called safely after build if needed

WidgetsBinding.instance.addPostFrameCallback((_) {

if (mounted) {

setState(() {});

}

});

}



// Enhanced reconnect function with timeout and active scanning

Future<void> _triggerReconnect() async {

// Use context before async gap

final service = Provider.of<OssmmBluetoothService>(context, listen: false);

final scaffoldMessenger = ScaffoldMessenger.of(context); // Capture ScaffoldMessenger



// If we're already in manual reconnect mode, treat this as a cancel action

if (_isPerformingManualReconnect) {

setState(() {

_isPerformingManualReconnect = false;

});



// Tell the service to cancel any reconnection attempts

if (service.isAttemptingAutoReconnect) {

service.cancelReconnectionAttempts();

}



print("Manual reconnection attempt cancelled by user.");

if (scaffoldMessenger.mounted) {

scaffoldMessenger.showSnackBar(

const SnackBar(

content: Text("Reconnection attempt cancelled."),

duration: Duration(seconds: 2),

)

);

}

return;

}



// Already attempting reconnection or connecting (but not by us)

if (service.isConnecting || service.isAttemptingAutoReconnect) {

print("Reconnect trigger ignored: Already connecting or reconnecting via another process.");

return;

}



// If user presses reconnect, they no longer intend for it to stay off

// Also indicate manual reconnect is starting

setState(() {

_deviceIntentionallyTurnedOff = false;

_isPerformingManualReconnect = true; // Show spinner

});



try {

print("Triggering manual reconnection...");

// Trigger reconnection attempt with the manual flag

final bool initialTriggerSuccess = await service.triggerBondedDeviceReconnection(isManualAttempt: true);



// Wait a short period to allow connection state to potentially update

await Future.delayed(const Duration(milliseconds: 500)); // Adjust delay if needed



// Check the actual connection state *after* the delay

// Show error only if the initial trigger reported failure AND we are still not connected/connecting

if (!initialTriggerSuccess && mounted && !service.isConnected && !service.isConnecting) { // Check mounted and connection states

print("Manual reconnection trigger reported failure and still not connected.");

// Check context is still valid before showing SnackBar

if (scaffoldMessenger.mounted) {

scaffoldMessenger.showSnackBar(

const SnackBar(

content: Text("Reconnection failed. Device may be turned off or out of range."),

duration: Duration(seconds: 3),

)

);

}

} else if (initialTriggerSuccess) {

print("Manual reconnection trigger successful (connection may still be in progress).");

} else if (service.isConnected) {

print("Manual reconnection successful (already connected after trigger).");

}



} catch (e) {

// Handle any errors during the trigger or delay

print("Error during manual reconnection: $e");

if (mounted && scaffoldMessenger.mounted) { // Check mounted and scaffold messenger validity

scaffoldMessenger.showSnackBar(

SnackBar(

content: Text("Reconnection error: ${e.toString()}"),

duration: const Duration(seconds: 3),

)

);

}

} finally {

// IMPORTANT: Only reset visual indicator if we're not still connecting

// This allows the Cancel button to appear during the connection process

if (mounted && !service.isAttemptingAutoReconnect && !service.isConnecting) {

setState(() {

_isPerformingManualReconnect = false; // Hide spinner

});

}

print("Manual reconnection attempt finished.");

}

}



// We're intentionally leaving this method empty to remove the "Reconnecting..." box

void _showConnectingDialog(BuildContext context) {

// Intentionally left empty as per requirements

}



Future<bool?> _showSaveDataDialog(BuildContext context) async {

if (!mounted) return null;

return showDialog<bool>(

context: context,

builder: (dialogContext) {

return AlertDialog(

title: const Text("Save Recording?"),

content: const Text("Do you want to save the collected data?"),

actions: [

TextButton( child: const Text("Discard"), onPressed: () => Navigator.of(dialogContext).pop(false), ),

TextButton( child: const Text("Save"), onPressed: () => Navigator.of(dialogContext).pop(true), ),

],

);

}

);

}



Future<void> _showConfirmForgetDevicesDialog(BuildContext context) async {

if (!mounted) return;

final service = context.read<OssmmBluetoothService>(); // Read service before async gap



final bool? result = await showDialog<bool>(

context: context,

builder: (dialogContext) {

return AlertDialog(

title: const Text("Forget All Paired Devices?"),

content: const Text(

"This will remove all bonded devices from the app. "

"You will need to reconnect and pair with devices again. "

"Are you sure you want to continue?"

),

actions: [

TextButton(

onPressed: () => Navigator.of(dialogContext).pop(false),

child: const Text("Cancel"),

),

TextButton(

style: TextButton.styleFrom(foregroundColor: Colors.red),

onPressed: () => Navigator.of(dialogContext).pop(true),

child: const Text("Forget All"),

),

],

);

},

);



// If user confirmed, call the service method to clear all bonded devices

if (result == true && mounted) { // Check mounted again after await

await service.clearAllBondedDevices();

// After forgetting devices, reset the intentional disconnect flag

setState(() {

_deviceIntentionallyTurnedOff = false;

});

}

}



Future<void> _showErrorDialog(BuildContext context, String title, String content) async {

if (!mounted) return;

await showDialog<void>(

context: context,

builder: (BuildContext dialogContext) {

return AlertDialog(

title: Text(title),

content: Text(content),

actions: <Widget>[ TextButton( child: const Text("Close"), onPressed: () => Navigator.of(dialogContext).pop(), ), ],

);

},

);

}



// --- Widget Build Method ---

@override

Widget build(BuildContext context) {

return Consumer<OssmmBluetoothService>(

builder: (context, service, child) {

// --- Determine UI States ---



// Reconnect Button Visibility Logic

// Show if: Bonded device exists AND not connected AND not actively connecting AND not manually reconnecting

bool showReconnectButton = service.bondedDevices.isNotEmpty &&

!service.isConnected &&

!service.isConnecting &&

!_isPerformingManualReconnect;



// Determine if stopping recording should also turn off device

bool stopAndTurnOff = service.autoReconnectToBonded || _startStopWithConnection;



// Determine if Auto-Reconnect Toggle should be enabled

// Enable if: Not actively connecting AND not manually reconnecting

bool isAutoReconnectToggleEnabled = !service.isConnecting && !_isPerformingManualReconnect;



// Determine if other connection/action buttons should be enabled

// Enable if: Not connecting, not disconnecting, and not manually reconnecting

bool canInitiateConnectionActions = !service.isConnecting &&

service.connectionState != DeviceConnectionState.disconnecting &&

!_isPerformingManualReconnect;





return Scaffold(

appBar: AppBar(

title: const Text('OSSMM Dashboard'),

actions: [

Padding(

padding: const EdgeInsets.only(right: 16.0),

child: Icon(

service.isConnected ? Icons.bluetooth_connected :

service.isConnecting ? Icons.bluetooth_searching :

Icons.bluetooth_disabled,

color: service.isConnected ? Colors.white :

service.isConnecting ? Colors.yellow : Colors.white54,

),

)

],

),

body: ListView(

padding: const EdgeInsets.all(8.0),

children: <Widget>[

// --- Connection Section ---

_buildSectionTitle(context, 'Connection'),

Row(

children: [

Expanded(

child: ListTile(

leading: const Icon(Icons.bluetooth),

title: Text('Status: ${service.connectionState.name}'),

subtitle: Column(

crossAxisAlignment: CrossAxisAlignment.start,

children: [

// Changed text from "Bonded Device:" to "Bonded to Device:" with "Yes" or "No" response

Text('Bonded to Device: ${service.bondedDevices.isNotEmpty ? "Yes" : "No"}'),

Text('Device: ${service.selectedDeviceName}'), // Name of currently connected/selected device

],

),

),

),

// Reconnect button - uses updated visibility logic

if (showReconnectButton)

Padding(

padding: const EdgeInsets.only(right: 16.0),

child: ElevatedButton(

// Disable if other connection actions are disabled

onPressed: canInitiateConnectionActions ? () => _triggerReconnect() : null,

style: ElevatedButton.styleFrom(

padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

),

child: Text(

_startStopWithConnection

? "Reconnect\nand\nRecord"

    : "Reconnect",

textAlign: TextAlign.center,

), // Changed from const Text("Reconnect")

),

),

// Show spinner within the button area if manually reconnecting

if (_isPerformingManualReconnect)

Padding(

padding: const EdgeInsets.only(right: 16.0),

child: ElevatedButton(

onPressed: () => _triggerReconnect(), // Call same method, but it will act as cancel

style: ElevatedButton.styleFrom(

padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),

backgroundColor: Colors.red.shade600,

),

child: const Row(

mainAxisSize: MainAxisSize.min,

children: [

SizedBox(

width: 16, height: 16,

child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),

),

SizedBox(width: 8),

Text("Cancel", style: TextStyle(color: Colors.white)),

],

),

),

),

],

),

const Divider(),



// --- Recording Section ---

_buildSectionTitle(context, 'Recording'),

Column(

crossAxisAlignment: CrossAxisAlignment.stretch,

children: [

ListTile(

leading: Icon(service.isRecording ? Icons.stop_circle_outlined : Icons.play_circle_outline),

title: Text(service.isRecording ? 'Recording Active' : 'Recording Stopped'),

subtitle: Text(service.isRecording ? 'Saving to: ${service.csvFilePath ?? "..."}' : 'Press Start to begin recording'),

),

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),

child: SizedBox(

width: double.infinity,

child: ElevatedButton.icon(

icon: Icon(service.isRecording ? Icons.stop : Icons.play_arrow),

// Updated button text to show "Stop Recording and Turn Off" when either toggle is enabled

label: Text(service.isRecording

? (stopAndTurnOff ? "Stop Recording and Turn Off" : "Stop Recording")

    : "Start Recording"),

style: ElevatedButton.styleFrom(

backgroundColor: service.isRecording

? (stopAndTurnOff ? Colors.red : Colors.orange)

    : Colors.green,

minimumSize: const Size(double.infinity, 48),

),

// Disable based on connection state and recording status

onPressed: service.isRecording

? (canInitiateConnectionActions // Can we interact?

? () async { // Modified to always show save dialog first

final service = context.read<OssmmBluetoothService>();

bool? saveData = await _showSaveDataDialog(context);

if (saveData != null && mounted) {

if (stopAndTurnOff) {

// Set flag indicating user intentionally turning off device

setState(() { _deviceIntentionallyTurnedOff = true; });

// Pass the saveData choice to the disconnect method

await service.disconnectAndTurnOffDevice(saveData: saveData);

} else {

// Just stop recording but don't disconnect

await service.stopRecording(saveData: saveData);

}

}

}

    : null // Disabled if cannot initiate actions

)

    : (canInitiateConnectionActions && service.isConnected && !service.isRecording // Can we start?

? () async { // Action: Start Recording

final service = context.read<OssmmBluetoothService>();

bool success = await service.startRecording();

if (!success && mounted) {

_showErrorDialog(context, "Recording Failed", "Could not start recording. Check permissions/connection/device.");

}

}

    : null // Disabled otherwise

),

),

),

),

],

),

const Divider(),



// --- Live Data Section ---

ExpansionTile(

title: _buildSectionTitle(context, 'Live Data'),

leading: const Icon(Icons.auto_graph),

initiallyExpanded: true,

children: <Widget>[

Builder(

builder: (context) {

final List<DataSample> chartSamples = service.getDownsampledSamples(

const Duration(seconds: 15));



bool hasChartData = chartSamples.isNotEmpty;

bool showChart = service.isConnected && hasChartData;



if (!service.isConnected && !service.isConnecting) {

return const Padding( padding: EdgeInsets.all(16.0), child: Text("Connect to a device to see live data."), );

} else if (service.isConnecting) {

return const Padding( padding: EdgeInsets.all(16.0), child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [ CircularProgressIndicator(), SizedBox(width: 15), Text("Connecting..."), ],), );

} else if (!service.isRecording && !hasChartData && service.isConnected) {

return const Padding( padding: EdgeInsets.all(16.0), child: Text("Start recording to view live data."), );

} else if (!hasChartData && service.isRecording) {

return const Padding( padding: EdgeInsets.all(16.0), child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [ CircularProgressIndicator(), SizedBox(width: 15), Text("Waiting for data..."), ],),);

} else if (showChart) {

return LiveDataChart(

samples: chartSamples,

displayDuration: const Duration(seconds: 15),

);

} else {

// Fallback case

return const Padding( padding: EdgeInsets.all(16.0), child: Text("Connect and start recording to view live data."), );

}

}

)

],

),

const Divider(),



// --- Modulation Section (Now Collapsible) ---

ExpansionTile(

title: _buildSectionTitle(context, 'Sleep Modulation'),

leading: const Icon(Icons.bedtime_outlined),

initiallyExpanded: false, // Start collapsed

children: <Widget>[

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),

child: SwitchListTile(

title: const Text("Modulation Mode"),

subtitle: Text(_modulationEnabled ? "Enabled (Test button active)" : "Disabled"),

value: _modulationEnabled,

// Disable if cannot initiate actions

onChanged: canInitiateConnectionActions

? (bool value) { setState(() { _modulationEnabled = value; }); }

    : null,

dense: true,

contentPadding: EdgeInsets.zero,

),

),

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),

child: SizedBox(

width: double.infinity,

child: ElevatedButton.icon(

icon: const Icon(Icons.send_outlined),

label: const Text('Test Modulation'), // Original Text

style: ElevatedButton.styleFrom(

minimumSize: const Size(double.infinity, 48),

),

// Disable if cannot initiate actions, not connected, or modulation disabled

onPressed: canInitiateConnectionActions && service.isConnected && _modulationEnabled

? () => context.read<OssmmBluetoothService>().testModulate()

    : null,

),

),

),

],

),

const Divider(),



// --- Settings Section (Collapsible) ---

ExpansionTile(

title: _buildSectionTitle(context, 'Settings'),

leading: const Icon(Icons.settings),

initiallyExpanded: false, // Start collapsed

children: <Widget>[

// Auto-Reconnect Toggle

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),

child: SwitchListTile(

title: const Text("Auto-Reconnect Bonded Device"), // Original Text

subtitle: const Text("Automatically reconnect when device is available"), // Original Text

value: service.autoReconnectToBonded,

// Disable only if actively connecting or manually reconnecting

onChanged: isAutoReconnectToggleEnabled

? (bool value) {

service.setAutoReconnectToBonded(value);

// If enabling auto-reconnect, disable start/stop with connection

if (value && _startStopWithConnection) {

setState(() {

_startStopWithConnection = false;

});

} else {

// Ensure UI rebuilds even if only service state changed

setState(() {});

}

}

    : null, // Disabled

dense: true,

contentPadding: EdgeInsets.zero,

),

),



// Start/Stop with Connection Toggle

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),

child: SwitchListTile(

title: const Text("Start/Stop with Connection"), // Original Text

subtitle: const Text("Starts recording on connection. Stops recording and shuts off headband on disconnect."), // Original Text

value: _startStopWithConnection,

// Disable if cannot initiate actions

onChanged: canInitiateConnectionActions

? (bool value) {

setState(() {

_startStopWithConnection = value;

// If enabling this, disable auto-reconnect

if (value && service.autoReconnectToBonded) {

service.setAutoReconnectToBonded(false);

}

});

}

    : null,

dense: true,

contentPadding: EdgeInsets.zero,

),

),



// Delete Unencrypted CSV Toggle - FIXED

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),

child: SwitchListTile(

title: const Text("Delete Unencrypted CSV Recording"),

subtitle: const Text("Keep only encrypted ZIP files after recording"),

value: service.deleteUnencryptedCsv,

onChanged: canInitiateConnectionActions

? (bool value) {

service.setDeleteUnencryptedCsv(value);

}

    : null,

dense: true,

contentPadding: EdgeInsets.zero,

),

),



// Connection buttons

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),

child: Row(

mainAxisAlignment: MainAxisAlignment.spaceEvenly,

children: [

// Find Device Button

Expanded(

child: Padding(

padding: const EdgeInsets.only(right: 8.0),

child: ElevatedButton.icon(

icon: const Icon(Icons.search),

label: const Text('Find Device'), // Original Text

style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),

// Disable if cannot initiate actions OR if connected

onPressed: canInitiateConnectionActions && !service.isConnected

? () async {

final service = context.read<OssmmBluetoothService>();

final navigator = Navigator.of(context);



final selectedDevice = await navigator.push<fbp.BluetoothDevice?>(

MaterialPageRoute(builder: (ctx) => const FindDevicesScreen()),

);

if (selectedDevice != null && mounted) {

// Reset intentional flag before connecting

if (_deviceIntentionallyTurnedOff) {

setState(() { _deviceIntentionallyTurnedOff = false; });

}

bool success = await service.connectToDevice(selectedDevice);

if (!success && mounted) {

// Use platformName here as selectedDevice is fbp.BluetoothDevice

_showErrorDialog(context, "Connection Failed",

"Could not connect to ${selectedDevice.platformName}. Please check device.");

}

}

}

    : null,

),

),

),

// Connect / Disconnect Button

Expanded(

child: Padding(

padding: const EdgeInsets.only(left: 8.0),

child: ElevatedButton.icon(

icon: Icon(

// Show cancel icon when reconnection is in progress

_isPerformingManualReconnect ? Icons.cancel :

// Otherwise show power icon for disconnect or link icon for connect

(service.isConnected ? Icons.power_settings_new : Icons.link)

),

// Update the label based on the current state

label: Text(

_isPerformingManualReconnect ? 'Cancel' :

(service.isConnected ? 'Disconnect' : 'Connect')

),

style: ElevatedButton.styleFrom(

// Use red for disconnect or cancel, otherwise default color

backgroundColor: (_isPerformingManualReconnect || service.isConnected) ? Colors.red : null,

minimumSize: const Size(0, 48),

),

// Update action based on current state

onPressed:

// If we're reconnecting, allow cancellation regardless of other states

_isPerformingManualReconnect ? () => _triggerReconnect() :

// Otherwise use normal action disabling logic

(canInitiateConnectionActions

? (!service.isConnected && service.bondedDevices.isNotEmpty)

// Call _triggerReconnect for bonded devices

? () => _triggerReconnect()

    : (service.isConnected)

// Logic to Disconnect

? () async {

final service = context.read<OssmmBluetoothService>();

setState(() {

_deviceIntentionallyTurnedOff = true; // User initiated disconnect

});

await service.disconnectAndTurnOffDevice(); // Or just disconnect()

}

    : null

    : null), // Disabled if cannot initiate actions

),

),

),

],

),

),



// Forget Paired Devices Button

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),

child: ElevatedButton.icon(

icon: const Icon(Icons.delete_outline),

label: const Text('Forget All Paired Devices'), // Original Text

style: ElevatedButton.styleFrom(

backgroundColor: Colors.red.shade50,

foregroundColor: Colors.red,

padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Adjusted padding

),

// Disable if cannot initiate actions OR no bonded devices

onPressed: canInitiateConnectionActions && service.bondedDevices.isNotEmpty

? () => _showConfirmForgetDevicesDialog(context)

    : null,

),

),

],

),

const Divider(),



// --- Data Protection Section ---

ExpansionTile(

title: _buildSectionTitle(context, 'Data Protection'),

leading: const Icon(Icons.security),

initiallyExpanded: false, // Start collapsed

children: <Widget>[

Padding(

padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),

child: Column(

crossAxisAlignment: CrossAxisAlignment.start,

children: [

const Padding(

padding: EdgeInsets.only(bottom: 12.0),

child: Text(

"Data is encrypted with a password when stored. You'll need this password to access recorded files.", // Original Text

style: TextStyle(fontSize: 14),

),

),

// Centered the button

Center(

child: ElevatedButton.icon(

icon: const Icon(Icons.password),

label: const Text('View Data Access Password'), // Original Text

style: ElevatedButton.styleFrom(

padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // Adjusted padding

),

onPressed: () => context.read<OssmmBluetoothService>().showDataAccessPassword(context),

),

),

],

),

)

],

),



// Added extra padding at the bottom for navigation bar clearance

const SizedBox(height: 80),

],

),

);

},

);

}



// Helper for section titles

Widget _buildSectionTitle(BuildContext context, String title) {

return Padding(

padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),

child: Text(

title,

style: Theme.of(context).textTheme.titleLarge?.copyWith(

color: Theme.of(context).primaryColor,

fontWeight: FontWeight.bold,

),

),

);

}

}