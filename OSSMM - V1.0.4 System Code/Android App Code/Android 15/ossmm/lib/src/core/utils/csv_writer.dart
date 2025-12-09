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


// lib/src/core/utils/csv_writer.dart

import 'dart:async';
import 'dart:io';
// import 'dart:convert'; // Not strictly needed for current logic, but can keep if planned
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:ossmm/src/core/models/data_sample.dart'; // Assuming this path is correct for your project
import 'package:archive/archive.dart'; // Needed for Archive, ArchiveFile, ZipFile constants
import 'package:archive/archive_io.dart'; // Needed for ZipFileEncoder, OutputFileStream etc.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Define a constant for the subdirectory name
const String _deviceDirectoryName = "OSSMM";

// Define the correct CSV header as a constant
const List<String> _correctCsvHeader = ['DateTime', 'transNum', 'eog', 'hr', 'accX', 'accY', 'accZ', 'gyroX', 'gyroY', 'gyroZ'];

class CsvWriterUtil {
  String? _currentFilePath; // Stores the path of the final output file (ZIP or CSV on failure)
  IOSink? _sink;
  bool _hasWrittenHeader = false;
  bool _isInitialized = false;
  final _secureStorage = FlutterSecureStorage();

  String? _tempCsvPath; // Specifically track the temporary CSV path

  String? get currentFilePath => _currentFilePath; // Returns the path of the final ZIP file (or temp CSV if zip failed)
  bool get isInitialized => _isInitialized;

  // _requestStoragePermission() is now deprecated for OSSMM
  // Request necessary permissions for Android
  /*
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      // var photosStatus = await Permission.photos.request(); (unused)
      // print("Photos (Media) permission request status: $photosStatus"); (unused)
      var storageStatus = await Permission.storage.request();
      print("Storage permission request status: $storageStatus");
      if (storageStatus.isGranted) {
        print("Sufficient permissions granted.");
        return true;
      } else {
        print("Permissions denied.");
        return false;
      }
    } else {
      return true;
    }
  }
   */

  // Generate or retrieve the encryption password
  Future<String> _getEncryptionPassword() async {
    String? password = await _secureStorage.read(key: 'ossmm_data_password');
    if (password == null || password.isEmpty) {
      final timestampPart = DateTime.now().millisecondsSinceEpoch.toString();
      password = 'OSSMM-${timestampPart.substring(timestampPart.length - 6)}';
      await _secureStorage.write(key: 'ossmm_data_password', value: password);
      print("Generated and stored new password.");
    } else {
      print("Retrieved existing password.");
    }
    return password;
  }

  // Show password dialog to the user
  Future<void> showDataAccessPassword(BuildContext context) async {
    try {
      final password = await _getEncryptionPassword();
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Data Access Password'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('Use this password to access the data files when connecting the device to a computer:'),
                const SizedBox(height: 16),
                Container(
                  color: Colors.grey[200],
                  padding: const EdgeInsets.all(8.0),
                  child: SelectableText(
                    password,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('This password protects all your recorded data files.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('I\'ve Noted This Password'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
    } catch (e) {
      print("Error showing password dialog: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error retrieving password: $e')),
        );
      }
    }
  }

  // Get the Documents directory path for secure storage
  Future<String> _getSecureDirectoryPath() async {
    final String documentsPath = '/storage/emulated/0/Documents'; // Consider using path_provider
    final String fullPath = path.join(documentsPath, _deviceDirectoryName);
    print("Using secure directory path: $fullPath");
    return fullPath;
  }

  // Prepare storage - ensures the target directory exists
  Future<bool> _prepareStorage() async {
    // Storage Permission deprecated in OSSMM app
    /*
    bool permissionsGranted = await _requestStoragePermission();
    if (!permissionsGranted) {
      print("Storage permissions not granted. Cannot prepare storage.");
      return false;
    }
    */
    try {
      final String securePath = await _getSecureDirectoryPath();
      final Directory dir = Directory(securePath);
      print("Target directory path for preparation: ${dir.path}");
      if (!await dir.exists()) {
        print("Attempting to create directory: ${dir.path}");
        try {
          await dir.create(recursive: true);
          print("Successfully called create directory.");
          if (!await dir.exists()) {
            print("Error: Directory still does not exist after attempting creation: ${dir.path}");
            return false;
          }
          print("Verified directory exists after creation: ${dir.path}");
          final readmeFile = File(path.join(dir.path, 'README.txt'));
          await readmeFile.writeAsString(
              'OSSMM Research Data Files\n\n'
                  'These ZIP files contain password-protected CSV data.\n'
                  'To access the CSV data inside, you will need the password shown in the OSSMM app (Settings -> Show Data Password).\n'
                  'Files are standard ZIP archives using ZipCrypto password protection.\n'
                  'Use 7-Zip (Recommended), WinZip, Keka (macOS), or your OS built-in utility (if it supports password-protected ZIPs) to open them.\n'
          );
          print("Created README.txt in new directory.");
        } catch (e) {
          print("Error creating directory ${dir.path}: $e");
          return false;
        }
      } else {
        print("Directory already exists: ${dir.path}");
      }
      print("Storage directory successfully prepared: ${dir.path}");
      return true;
    } catch (e, stacktrace) {
      print("Error preparing storage directory: $e");
      print("Stacktrace: $stacktrace");
      return false;
    }
  }

  // Initialize writer: Creates a temporary CSV file in the prepared storage path
  Future<bool> initialize() async {
    if (_isInitialized) {
      print("CSV Writer already initialized.");
      return true;
    }
    bool storageReady = await _prepareStorage();
    if (!storageReady) {
      print("Storage not ready, cannot initialize CsvWriterUtil.");
      return false;
    }
    try {
      String recordingStartTime = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final String securePath = await _getSecureDirectoryPath();
      _tempCsvPath = path.join(securePath, "temp_$recordingStartTime.csv");
      final file = File(_tempCsvPath!);
      final parentDir = file.parent;
      if (!await parentDir.exists()){
        print("Error: Parent directory ${parentDir.path} does not exist before creating file.");
        await parentDir.create(recursive: true);
        if (!await parentDir.exists()){
          print("Error: Failed to create parent directory ${parentDir.path}. Cannot initialize.");
          return false;
        }
      }
      _sink = file.openWrite();
      print("Opened temporary CSV file for writing: $_tempCsvPath");

      // FIXED BUG: Set these flags BEFORE writing the header
      _hasWrittenHeader = true;
      _isInitialized = true;

      // Now write the header with the correct flags set
      _writeRow(_correctCsvHeader);
      print("Written correct CSV header: $_correctCsvHeader");

      _currentFilePath = null;
      print("CSV Writer Initialized successfully.");
      return true;
    } catch (e, stacktrace) {
      print("Error initializing CSV writer: $e");
      print("Stacktrace: $stacktrace");
      _tempCsvPath = null;
      _currentFilePath = null;
      _sink = null;
      _isInitialized = false;
      return false;
    }
  }

  // Writes a single row to the CSV file, handling quoting and escaping.
  void _writeRow(List<dynamic> row) {
    if (_sink == null || !_isInitialized) {
      print('Warning: CSV Writer not initialized or sink is null. Cannot write row.');
      return;
    }
    final formattedRow = row.map((field) {
      String safeField = field?.toString() ?? "";
      String escapedField = safeField.replaceAll('"', '""');
      if (escapedField.contains(',') || escapedField.contains('"') || escapedField.contains('\n')) {
        return '"$escapedField"';
      }
      return escapedField;
    }).join(',');
    try {
      _sink!.writeln(formattedRow);
    } catch (e) {
      print("Error writing line to CSV: $e");
    }
  }

  // Appends a DataSample to the CSV file.
  void appendSample(DataSample sample) {
    if (!_isInitialized || _sink == null) {
      print("Warning: Cannot append sample, writer not initialized.");
      return;
    }
    _writeRow(sample.toCsvRow());
  }


  /// Creates a password-protected ZIP file using ZipFileEncoder.
  /// Password protection is applied via the constructor.
  Future<String?> _createProtectedZip({
    required String sourceFilePath, // Path to the temporary CSV file
    required String password
  }) async {
    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      print('Error creating ZIP: Source file $sourceFilePath does not exist.');
      return null;
    }
    if (await sourceFile.length() == 0) {
      print('Warning creating ZIP: Source file $sourceFilePath is empty.');
    }

    // --- Define Paths ---
    final fileNameInZip = path.basename(sourceFilePath).replaceAll('temp_', '');
    final baseName = path.basenameWithoutExtension(sourceFilePath).replaceAll('temp_', '');
    final secureDir = await _getSecureDirectoryPath();
    final zipPath = path.join(secureDir, 'OSSMM_$baseName.zip');

    print("Preparing to create ZIP using ZipFileEncoder (Password in Constructor): $zipPath");
    print("File to add inside ZIP: $fileNameInZip");
    print("Source CSV file: $sourceFilePath");

    // --- Use ZipFileEncoder with Password in Constructor ---
    // *** Apply password here ***
    final zipEncoder = ZipFileEncoder(password: password);

    try {
      // 1. Create the empty zip file structure on disk
      zipEncoder.create(zipPath);
      print("Created empty ZIP file structure at $zipPath");

      // 2. Add the source file to the zip.
      //    Provide the filename as the second positional argument.
      //    Use default compression level by omitting the third argument.
      //    Password is implicitly applied based on the encoder's setup.
      await zipEncoder.addFile(
          sourceFile,        // The File object to add
          fileNameInZip     // The desired name for the file *inside* the ZIP archive (positional)
        // No level, method, or password args here
      );
      print("Added $fileNameInZip to ZIP. Password applied via constructor.");

      // 3. Close the encoder to finalize the zip file writing process
      zipEncoder.close(); // Synchronous
      print("Successfully closed and finalized password-protected ZIP file: $zipPath");
      return zipPath; // Return the path of the created ZIP file

    } catch (e, stacktrace) {
      print('Error during ZipFileEncoder operation (create/addFile/close) for $zipPath: $e');
      print('Stacktrace: $stacktrace');
      // Attempt to clean up the potentially broken/incomplete zip file
      try {
        final partialFile = File(zipPath);
        if (await partialFile.exists()) {
          await partialFile.delete();
          print("Deleted potentially incomplete ZIP file due to error: $zipPath");
        }
      } catch (delErr) {
        print("Error trying to delete incomplete ZIP file $zipPath after primary error: $delErr");
      }
      return null; // Indicate failure
    }
  }


  // Close the current CSV writer, create the protected ZIP, and clean up.
  // Added deleteUnencryptedCsv parameter with default value true
  Future<void> close({bool deleteUnencryptedCsv = true}) async {
    if (!_isInitialized || _sink == null) {
      print("Close called but writer was not initialized or already closed.");
      return;
    }
    final String? tempCsvPathToProcess = _tempCsvPath;
    print("Closing CSV writer...");
    try {
      await _sink!.flush();
      await _sink!.close();
      print("Closed temporary CSV file: $tempCsvPathToProcess");
    } catch(e, stacktrace) {
      print("Error flushing/closing CSV sink for $tempCsvPathToProcess: $e");
      print("Stacktrace: $stacktrace");
    }
    _sink = null;
    _hasWrittenHeader = false;
    _isInitialized = false;
    _tempCsvPath = null;
    if (tempCsvPathToProcess != null && tempCsvPathToProcess.isNotEmpty) {
      final tempFile = File(tempCsvPathToProcess);
      if (!await tempFile.exists()) {
        print("Error: Temporary CSV file $tempCsvPathToProcess not found after closing sink. Cannot create ZIP.");
        _currentFilePath = null;
        return;
      }
      if (await tempFile.length() == 0) {
        print("Warning: Temporary CSV file $tempCsvPathToProcess is empty. Proceeding to zip...");
      }
      final password = await _getEncryptionPassword();
      if (password.isEmpty) {
        print("Error: Could not retrieve or generate a valid password. Cannot create protected ZIP.");
        _currentFilePath = tempCsvPathToProcess;
        return;
      }
      print("Attempting to create password-protected ZIP from $tempCsvPathToProcess...");
      final zipPath = await _createProtectedZip(
          sourceFilePath: tempCsvPathToProcess,
          password: password
      );
      if (zipPath != null && zipPath.isNotEmpty) {
        print("Successfully created protected ZIP: $zipPath");
        _currentFilePath = zipPath;

        // Only delete if specified by parameter
        if (deleteUnencryptedCsv) {
          try {
            await tempFile.delete();
            print("Deleted temporary CSV file: $tempCsvPathToProcess");
          } catch (e) {
            print("Error deleting temporary CSV file $tempCsvPathToProcess after zipping: $e");
          }
        } else {
          print("Keeping unencrypted CSV file as requested: $tempCsvPathToProcess");
        }
      } else {
        print("Failed to create protected ZIP. The temporary CSV file $tempCsvPathToProcess has been kept.");
        _currentFilePath = tempCsvPathToProcess;
      }
    } else {
      print("Close called, but there was no valid temporary CSV file path to process.");
      _currentFilePath = null;
    }
    print("CSV Writer close process finished. Final file path: $_currentFilePath");
  }


  /// Deletes the currently referenced file (either the final ZIP or the temporary CSV if close failed).
  /// Ensures the writer is closed first.
  Future<void> deleteCurrentFile() async {
    if (_isInitialized || _sink != null) {
      print("Writer still active. Closing before deleting...");
      await close();
    }
    final String? pathToDelete = _currentFilePath;
    print("Attempting to delete file: $pathToDelete");
    if (pathToDelete != null && pathToDelete.isNotEmpty) {
      try {
        final file = File(pathToDelete);
        if (await file.exists()) {
          await file.delete();
          print("Successfully deleted file: $pathToDelete");
        } else {
          print("File to delete was not found (already deleted?): $pathToDelete");
        }
      } catch (e) {
        print("Error deleting file $pathToDelete: $e");
      }
      _currentFilePath = null;
    } else {
      print("No current file path to delete.");
    }
  }
}