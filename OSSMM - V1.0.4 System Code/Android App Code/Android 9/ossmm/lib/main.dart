/*
Title: OSSMM (WakeLift) Prototype App v0.9.1
By: Jonny Giordano
Date: Redesigned on January 12th, 2022
Last Update: August, 2022
Last Update: March, 2024
Last Update: April 19th, 2024
Last Update: May 1st, 2025

Other:
*/

// Import Packages
import 'package:flutter/material.dart';

// Import Pages
import 'package:wakelift/pages/main_page.dart';
import 'package:wakelift/pages/settings.dart';

void main() => runApp(MaterialApp(
  routes: {
    '/': (context) => const Home(),
    '/settings': (context) => const Settings(),
    //'/SelectDevicePage': (context) => const FindDevicesScreen(),
  },
));