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


// lib/src/features/data_display/widgets/live_data_chart.dart

import 'package:flutter/material.dart';
import 'package:ossmm/src/core/models/data_sample.dart';
import '../../../shared/widgets/LineChart.dart';

class LiveDataChart extends StatelessWidget {
  final List<DataSample> samples;
  final Duration displayDuration;
  // Removed unused downsampleFactor

  const LiveDataChart({
    super.key,
    required this.samples,
    this.displayDuration = const Duration(seconds: 15),
    // Removed downsampleFactor from constructor
  });

  // Helper to build section headers
  Widget _buildSectionHeader(BuildContext context, IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Data preparation and label configuration remain the same...
    if (samples.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text("Start recording or wait for data..."),
        ),
      );
    }

    final int argumentsShift = samples.first.timestamp.millisecondsSinceEpoch;
    final Iterable<double> arguments = samples.map((sample) {
      return (sample.timestamp.millisecondsSinceEpoch - argumentsShift).toDouble();
    });

    // Determine X-axis label step based on display duration
    final Duration argumentsStep;
    if (displayDuration.inSeconds > 120) { // 2+ minutes
      argumentsStep = const Duration(minutes: 1);
    } else if (displayDuration.inSeconds > 30) { // 30s to 2 mins
      argumentsStep = const Duration(seconds: 10);
    } else { // Up to 30s
      argumentsStep = const Duration(seconds: 5);
    }

    // Calculate timestamps for X-axis labels
    final DateTime beginningArguments = samples.first.timestamp;
    DateTime beginningArgumentsStep = DateTime(
        beginningArguments.year,
        beginningArguments.month,
        beginningArguments.day,
        beginningArguments.hour,
        beginningArguments.minute,
        (beginningArguments.second ~/ argumentsStep.inSeconds) * argumentsStep.inSeconds
    );
    // Adjust starting label timestamp if needed
    if (beginningArgumentsStep.isBefore(beginningArguments)) {
      beginningArgumentsStep = beginningArgumentsStep.add(argumentsStep);
    }
    if (beginningArgumentsStep.difference(beginningArguments).abs() > argumentsStep) {
      beginningArgumentsStep = beginningArgumentsStep.subtract(argumentsStep);
    }


    final DateTime endingArguments = samples.last.timestamp;
    final Iterable<DateTime> argumentsLabelsTimestamps = () sync* {
      DateTime timestamp = beginningArgumentsStep;
      // Ensure the first label isn't too far before the actual start
      if (timestamp.isAfter(beginningArguments.subtract(const Duration(seconds:1)))) {
        yield timestamp;
      }
      timestamp = timestamp.add(argumentsStep); // Move to the next potential label time

      while (timestamp.isBefore(endingArguments.add(argumentsStep))) {
        // Only yield labels that are at or after the first data point's time
        if(timestamp.isAfter(beginningArguments.subtract(const Duration(seconds: 1)))) {
          yield timestamp;
        }
        timestamp = timestamp.add(argumentsStep);
      }
    }();

    final Iterable<LabelEntry> argumentsLabels = argumentsLabelsTimestamps.map((timestamp) {
      final String label = "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}";
      final double labelValue = (timestamp.millisecondsSinceEpoch - argumentsShift).toDouble();
      return LabelEntry(labelValue, label);
    });


    // Styles and Dimensions
    const double chartHeight = 350.0;
    const PaintStyle verticalLinesStyle = PaintStyle(color: Colors.grey);
    const EdgeInsets chartPadding = EdgeInsets.fromLTRB(32, 12, 20, 28); // Adjusted padding a bit
    final List<PaintStyle> accLinesStyles = [ const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.indigoAccent), const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.pink), const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.black), ]; // Thinner lines
    final List<PaintStyle> gyroLinesStyles = [ const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.indigoAccent), const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.pink), const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.black), ]; // Thinner lines
    final List<PaintStyle> eogLinesStyles = [ const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.indigoAccent), ]; // Thinner lines
    final List<PaintStyle> hrLinesStyles = [ const PaintStyle(style: PaintingStyle.stroke, strokeWidth: 2, color: Colors.pink), ]; // Thinner lines
    final List<PaintStyle?> noPointsStyle = [null]; // Common style for no points

    // The rest of the build method using these parameters...
    return Column(
      children: <Widget>[
        _buildSectionHeader(context, Icons.show_chart, 'Accelerometer', 'X=Indigo, Y=Pink, Z=Black'),
        LineChart(
          constraints: const BoxConstraints.expand(height: chartHeight),
          padding: chartPadding,
          arguments: arguments,
          argumentsLabels: argumentsLabels,
          values: [ samples.map((s) => s.accX.toDouble()), samples.map((s) => s.accY.toDouble()), samples.map((s) => s.accZ.toDouble()), ],
          verticalLinesStyle: verticalLinesStyle,
          horizontalLinesStyle: const PaintStyle(color: Colors.grey),
          additionalMinimalHorizontalLabelsInterval: 0,
          additionalMinimalVerticalLablesInterval: 0,
          seriesPointsStyles: [null, null, null], // No points for acc
          seriesLinesStyles: accLinesStyles,
          snapToTopLabel: false,
          snapToBottomLabel: false,
        ),
        const Divider(),
        _buildSectionHeader(context, Icons.rotate_right, 'Gyroscope', 'X=Indigo, Y=Pink, Z=Black'),
        LineChart(
          constraints: const BoxConstraints.expand(height: chartHeight),
          padding: chartPadding,
          arguments: arguments,
          argumentsLabels: argumentsLabels,
          values: [ samples.map((s) => s.gyroX.toDouble()), samples.map((s) => s.gyroY.toDouble()), samples.map((s) => s.gyroZ.toDouble()), ],
          verticalLinesStyle: verticalLinesStyle,
          horizontalLinesStyle: const PaintStyle(color: Colors.grey),
          additionalMinimalHorizontalLabelsInterval: 0,
          additionalMinimalVerticalLablesInterval: 0,
          seriesPointsStyles: [null, null, null], // No points for gyro
          seriesLinesStyles: gyroLinesStyles,
          snapToTopLabel: false,
          snapToBottomLabel: false,
        ),
        const Divider(),
        _buildSectionHeader(context, Icons.visibility_outlined, 'EOG', 'Eye Movement Data'),
        LineChart(
          constraints: const BoxConstraints.expand(height: chartHeight),
          padding: chartPadding,
          arguments: arguments,
          argumentsLabels: argumentsLabels,
          values: [ samples.map((s) => s.eog.toDouble()), ],
          verticalLinesStyle: verticalLinesStyle,
          horizontalLinesStyle: const PaintStyle(color: Colors.grey),
          additionalMinimalHorizontalLabelsInterval: 0,
          additionalMinimalVerticalLablesInterval: 0,
          seriesPointsStyles: noPointsStyle,
          seriesLinesStyles: eogLinesStyles,
          snapToTopLabel: false,
          snapToBottomLabel: false,
        ),
        const Divider(),
        _buildSectionHeader(context, Icons.favorite_border, 'Heart Rate', 'Pulse Sensor Data'),
        LineChart(
          constraints: const BoxConstraints.expand(height: chartHeight),
          padding: chartPadding,
          arguments: arguments,
          argumentsLabels: argumentsLabels,
          values: [ samples.map((s) => s.hr.toDouble()), ],
          verticalLinesStyle: verticalLinesStyle,
          horizontalLinesStyle: const PaintStyle(color: Colors.grey),
          additionalMinimalHorizontalLabelsInterval: 0,
          additionalMinimalVerticalLablesInterval: 0,
          seriesPointsStyles: noPointsStyle,
          seriesLinesStyles: hrLinesStyles,
          snapToTopLabel: false,
          snapToBottomLabel: false,
        ),
      ],
    );
  }
}