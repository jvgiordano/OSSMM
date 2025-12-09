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

// lib/src/shared/widgets/LineChart.dart

/// @name LineChart
/// @version N/A
/// @description Simple line chart widget
/// @author Patryk "PsychoX" Ludwikowski <patryk.ludwikowski.7+dart@gmail.com>
/// @license MIT License (see https://mit-license.org/)
///
/// Note: The inspiration for this code was from PsychoX's original LineChart.dart
/// file. This script was merged with a PaintStyle.dart file using an LLM for
/// assistance. Because it is a derivative work with substantial borrowing,
/// keeping the MIT license here and giving credit to PsychoX is more that
/// justified. I'd also like to thank PsychoX for personally helping when I
/// had questions with the code, even though he hadn't seen it in years!
///
/// -Jonny
///


import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// --- PaintStyle Definition ---
// (PaintStyle class remains unchanged, using the version from the current code)
class PaintStyle {
  final bool isAntiAlias;
  static const int _kColorDefault = 0xFF000000;
  final Color? color;
  static final int _kBlendModeDefault = BlendMode.srcOver.index;
  final BlendMode blendMode;
  final PaintingStyle style;
  final double strokeWidth;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  static const double _kStrokeMiterLimitDefault = 4.0;
  final double strokeMiterLimit;
  final MaskFilter? maskFilter;
  final FilterQuality filterQuality;
  final Shader? shader;
  final ColorFilter? colorFilter;
  final bool invertColors;

  const PaintStyle({
    this.isAntiAlias = true,
    this.color = const Color(_kColorDefault),
    this.blendMode = BlendMode.srcOver,
    this.style = PaintingStyle.fill,
    this.strokeWidth = 0.0,
    this.strokeCap = StrokeCap.butt,
    this.strokeJoin = StrokeJoin.miter,
    this.strokeMiterLimit = 4.0,
    this.maskFilter,
    this.filterQuality = FilterQuality.none,
    this.shader,
    this.colorFilter,
    this.invertColors = false,
  });

  @override
  String toString() {
    final StringBuffer result = StringBuffer(); String semicolon = '';
    result.write('PaintStyle(');
    if (style == PaintingStyle.stroke) { result.write('$style'); if (strokeWidth != 0.0) { result.write(' ${strokeWidth.toStringAsFixed(1)}'); } else { result.write(' hairline'); } if (strokeCap != StrokeCap.butt) result.write(' $strokeCap'); if (strokeJoin == StrokeJoin.miter) { if (strokeMiterLimit != _kStrokeMiterLimitDefault) { result.write( ' $strokeJoin up to ${strokeMiterLimit.toStringAsFixed(1)}'); } } else { result.write(' $strokeJoin'); } semicolon = '; '; }
    if (isAntiAlias != true) { result.write('${semicolon}antialias off'); semicolon = '; '; }
    if (color != const Color(_kColorDefault)) { if (color != null) { result.write('$semicolon$color'); } else { result.write('${semicolon}no color'); } semicolon = '; '; }
    if (blendMode.index != _kBlendModeDefault) { result.write('$semicolon$blendMode'); semicolon = '; '; }
    if (colorFilter != null) { result.write('${semicolon}colorFilter: $colorFilter'); semicolon = '; '; }
    if (maskFilter != null) { result.write('${semicolon}maskFilter: $maskFilter'); semicolon = '; '; }
    if (filterQuality != FilterQuality.none) { result.write('${semicolon}filterQuality: $filterQuality'); semicolon = '; '; }
    if (shader != null) { result.write('${semicolon}shader: $shader'); semicolon = '; '; }
    if (invertColors) result.write('${semicolon}invert: $invertColors');
    result.write(')'); return result.toString();
  }

  Paint toPaint() {
    Paint paint = Paint();
    if (isAntiAlias != true) paint.isAntiAlias = isAntiAlias;
    if (color != const Color(_kColorDefault)) paint.color = color!;
    if (blendMode != BlendMode.srcOver) paint.blendMode = blendMode;
    if (style != PaintingStyle.fill) paint.style = style;
    if (strokeWidth != 0.0) paint.strokeWidth = strokeWidth;
    if (strokeCap != StrokeCap.butt) paint.strokeCap = strokeCap;
    if (strokeJoin != StrokeJoin.miter) paint.strokeJoin = strokeJoin;
    if (strokeMiterLimit != 4.0) { paint.strokeMiterLimit = strokeMiterLimit; }
    if (maskFilter != null) paint.maskFilter = maskFilter;
    if (filterQuality != FilterQuality.none) paint.filterQuality = filterQuality;
    if (shader != null) paint.shader = shader;
    if (colorFilter != null) paint.colorFilter = colorFilter;
    if (invertColors != false) paint.invertColors = invertColors;
    return paint;
  }
}

class LabelEntry {
  final double value;
  final String label;
  LabelEntry(this.value, this.label);
}

// --- LineChart Class ---
// (LineChart widget class remains unchanged from the current version)
class LineChart extends StatelessWidget {
  final BoxConstraints constraints;
  final EdgeInsets padding;
  final Iterable<double> arguments;
  final Iterable<LabelEntry> argumentsLabels;
  final Iterable<Iterable<double>> values;
  final TextStyle? horizontalLabelsTextStyle;
  final TextStyle? verticalLabelsTextStyle;
  final Paint horizontalLinesPaint;
  final Paint verticalLinesPaint;
  final bool snapToLeftLabel;
  final bool snapToTopLabel;
  final bool snapToRightLabel;
  final bool snapToBottomLabel;
  final List<Paint?> seriesPointsPaints;
  final List<Paint>? seriesLinesPaints;
  final double additionalMinimalHorizontalLabelsInterval;
  final double additionalMinimalVerticalLablesInterval;
  final double _finalMinimalHorizontalLabelsInterval;

  LineChart({super.key,
    required this.constraints,
    this.padding = const EdgeInsets.fromLTRB(32, 12, 20, 28),
    required this.arguments,
    required this.argumentsLabels,
    required this.values,
    this.horizontalLabelsTextStyle,
    this.verticalLabelsTextStyle,
    PaintStyle horizontalLinesStyle = const PaintStyle(color: Colors.grey),
    PaintStyle? verticalLinesStyle,
    this.snapToLeftLabel = false, this.snapToTopLabel = true,
    this.snapToRightLabel = false, this.snapToBottomLabel = true,
    this.additionalMinimalHorizontalLabelsInterval = 0,
    this.additionalMinimalVerticalLablesInterval = 0,
    List<PaintStyle?>? seriesPointsStyles,
    List<PaintStyle>? seriesLinesStyles,
    List<Paint?>? seriesPointsPaints,
    List<Paint>? seriesLinesPaints,
    Paint? horizontalLinesPaint,
    Paint? verticalLinesPaint,
  })  : seriesPointsPaints = seriesPointsPaints ?? _LineChartStatics._prepareSeriesPointsPaints(seriesPointsStyles),
        seriesLinesPaints = seriesLinesPaints ?? _LineChartStatics._prepareSeriesLinesPaints(seriesLinesStyles),
        horizontalLinesPaint = horizontalLinesPaint ?? horizontalLinesStyle.toPaint(),
        verticalLinesPaint = verticalLinesPaint ?? verticalLinesStyle?.toPaint() ?? PaintStyle(color: Colors.grey).toPaint(),
        _finalMinimalHorizontalLabelsInterval = (horizontalLabelsTextStyle?.fontSize ?? 12) + additionalMinimalHorizontalLabelsInterval
  {
    // Validation
    final resolvedPointsCount = this.seriesPointsPaints.length;
    final resolvedLinesCount = this.seriesLinesPaints?.length ?? 0;
    final valuesCount = values.length;
    final defaultPointPaints = _LineChartStatics._prepareSeriesPointsPaints(null);
    if (resolvedPointsCount < valuesCount && defaultPointPaints.length < valuesCount) { print("Warning: Fewer series points paints ($resolvedPointsCount) than data series ($valuesCount)."); }
    if (this.seriesLinesPaints != null && resolvedLinesCount < valuesCount) { print("Warning: Fewer series lines paints ($resolvedLinesCount) than data series ($valuesCount)."); }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHorizontalTextStyle = horizontalLabelsTextStyle ?? Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10);
    final effectiveVerticalTextStyle = verticalLabelsTextStyle ?? Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10);

    return ConstrainedBox(
        constraints: constraints,
        child: CustomPaint(
            painter: _LineChartPainter(
              padding: padding,
              arguments: arguments,
              argumentsLabels: argumentsLabels,
              values: values,
              horizontalLabelsTextStyle: effectiveHorizontalTextStyle,
              verticalLabelsTextStyle: effectiveVerticalTextStyle,
              horizontalLinesPaint: horizontalLinesPaint,
              verticalLinesPaint: verticalLinesPaint,
              additionalMinimalHorizontalLabelsInterval: additionalMinimalHorizontalLabelsInterval,
              additionalMinimalVerticalLablesInterval: additionalMinimalVerticalLablesInterval,
              seriesPointsPaints: seriesPointsPaints,
              seriesLinesPaints: seriesLinesPaints,
              snapToLeftLabel: snapToLeftLabel,
              snapToTopLabel: snapToTopLabel,
              snapToRightLabel: snapToRightLabel,
              snapToBottomLabel: snapToBottomLabel,
            )
        )
    );
  }
}

// --- Static Helpers ---
// (_LineChartStatics extension remains unchanged from the current version)
extension _LineChartStatics on LineChart {
  static List<Paint?> _prepareSeriesPointsPaints(Iterable<PaintStyle?>? seriesPointsStyles) {
    if (seriesPointsStyles == null) { return List<Paint?>.unmodifiable(<Paint>[ PaintStyle(strokeWidth: 1.7, color: Colors.blue).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.red).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.yellow).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.green).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.purple).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.deepOrange).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.brown).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.lime).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.indigo).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.pink).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.amber).toPaint(), PaintStyle(strokeWidth: 1.7, color: Colors.teal).toPaint(), ]); }
    else { return seriesPointsStyles.map((style) => style?.toPaint()).toList(); }
  }

  static List<Paint>? _prepareSeriesLinesPaints(Iterable<PaintStyle>? seriesLinesStyles) {
    if (seriesLinesStyles == null) { return null; }
    else { return seriesLinesStyles.map((style) => style.toPaint()).toList(); }
  }
}

// --- _LineChartPainter Class ---
class _LineChartPainter extends CustomPainter {
  final EdgeInsets padding;
  final Iterable<double> arguments;
  final Iterable<LabelEntry> argumentsLabels;
  final Iterable<Iterable<double>> values;
  final TextStyle? horizontalLabelsTextStyle;
  final TextStyle? verticalLabelsTextStyle;
  final Paint? horizontalLinesPaint;
  final Paint? verticalLinesPaint;
  final bool snapToLeftLabel;
  final bool snapToTopLabel;
  final bool snapToRightLabel;
  final bool snapToBottomLabel;
  final List<Paint?> seriesPointsPaints;
  final List<Paint>? seriesLinesPaints;
  final double minimalHorizontalLabelsInterval;
  final double additionalMinimalVerticalLablesInterval;
  final double maxValue; // Max value found in current data
  final double minValue; // Min value found in current data
  final double _minimalHorizontalRatio;

  _LineChartPainter({
    required this.padding,
    required this.arguments,
    required this.argumentsLabels,
    required this.values,
    required this.horizontalLabelsTextStyle,
    required this.verticalLabelsTextStyle,
    required this.horizontalLinesPaint,
    required this.verticalLinesPaint,
    required double additionalMinimalHorizontalLabelsInterval,
    required this.additionalMinimalVerticalLablesInterval,
    required this.seriesPointsPaints,
    required this.seriesLinesPaints,
    required this.snapToLeftLabel,
    required this.snapToTopLabel,
    required this.snapToRightLabel,
    required this.snapToBottomLabel,
  }) : minimalHorizontalLabelsInterval = (horizontalLabelsTextStyle?.fontSize ?? 12) + additionalMinimalHorizontalLabelsInterval,
  // Calculate raw min/max from the data passed in
        minValue = _calculateDataMin(values),
        maxValue = _calculateDataMax(values),
        _minimalHorizontalRatio = _calculateMinimalHorizontalRatio(argumentsLabels, verticalLabelsTextStyle, additionalMinimalVerticalLablesInterval);

  // --- Static helper methods ---
  static double _calculateDataMin(Iterable<Iterable<double>> dataValues) {
    double minVal = double.maxFinite;
    bool hasFiniteData = false;
    for (Iterable<double> series in dataValues) {
      if (series.isNotEmpty) {
        for (double value in series) {
          if (value.isFinite) {
            hasFiniteData = true;
            if (value < minVal) minVal = value;
          }
        }
      }
    }
    return hasFiniteData ? minVal : 0.0;
  }

  static double _calculateDataMax(Iterable<Iterable<double>> dataValues) {
    double maxVal = -double.maxFinite;
    bool hasFiniteData = false;
    for (Iterable<double> series in dataValues) {
      if (series.isNotEmpty) {
        for (double value in series) {
          if (value.isFinite) {
            hasFiniteData = true;
            if (value > maxVal) maxVal = value;
          }
        }
      }
    }
    return hasFiniteData ? maxVal : 1.0; // Default max to 1 if no data
  }

  static double _calculateMinimalHorizontalRatio(Iterable<LabelEntry> argLabels, TextStyle? style, double interval) {
    double ratio = 0;
    if (argLabels.isNotEmpty) {
      Iterator<LabelEntry> entry = argLabels.iterator;
      if (entry.moveNext()) {
        double lastValue = entry.current.value; double lastWidth = _getLabelTextPainterStatic(entry.current.label, style).width;
        while (entry.moveNext()) {
          final double nextValue = entry.current.value; final double nextWidth = _getLabelTextPainterStatic(entry.current.label, style).width;
          final double diff = nextValue - lastValue;
          if (diff > 1e-9) { final double requiredWidth = (lastWidth + nextWidth) / 2 + interval; final double goodRatio = requiredWidth / diff; if (goodRatio > ratio) { ratio = goodRatio; } }
          lastValue = nextValue; lastWidth = nextWidth;
        }
      }
    } return ratio > 0 ? ratio : 0;
  }

  static TextPainter _getLabelTextPainterStatic(String text, TextStyle? style) {
    return TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  }
  // --- End Static Helpers ---

  TextPainter _getLabelTextPainter(String text, TextStyle? style) {
    return TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  }

  // (Using the improved _calculateOptimalStepValue from the current version)
  double _calculateOptimalStepValue(double valueRange, double height) {
    final int maxSteps = height ~/ minimalHorizontalLabelsInterval;
    if (maxSteps <= 1) {
      // If not enough space for multiple steps, return the whole range
      // or a small default if range is zero
      return valueRange > 1e-10 ? valueRange : 0.1;
    }

    // Target 4-7 steps for a clean-looking chart
    final targetSteps = math.min(maxSteps, 7);
    double interval = valueRange / targetSteps;

    // Handle zero or extremely small range
    if (!interval.isFinite || interval.isNaN || interval < 1e-10) {
      return 0.1; // Return a small default step
    }

    // Find a "nice" step value (1, 2, 5, 10, 20, 50, etc.)
    double magnitude = 1.0;
    if (interval >= 10) {
      while (interval >= 10) {
        interval /= 10;
        magnitude *= 10;
      }
    } else if (interval < 1) {
      while (interval < 1) {
        interval *= 10;
        magnitude /= 10;
      }
    }

    double niceStep;
    if (interval <= 1.5) niceStep = 1.0;
    else if (interval <= 3) niceStep = 2.0;
    else if (interval <= 7) niceStep = 5.0;
    else niceStep = 10.0;

    return niceStep * magnitude;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width - padding.left - padding.right;
    final double height = size.height - padding.top - padding.bottom;
    if (width <= 0 || height <= 0) return;

    /* --- Y Axis Setup (Simplified based on old code's approach) --- */
    double valuesOffset = 0;
    double verticalRatio = 1.0;
    double bottomValue = 0;
    double topValue = 1; // Default range 0-1 if no data

    // Use the raw minValue and maxValue calculated in the constructor
    final double rawMinValue = minValue;
    final double rawMaxValue = maxValue;
    double dataRange = rawMaxValue - rawMinValue;

    // Handle case where min == max or range is effectively zero
    if (dataRange < 1e-10) {
      // Create an artificial range around the single value
      final double centerValue = rawMinValue; // or rawMaxValue, they are the same
      final double artificialRange = math.max(centerValue.abs() * 0.2, 1.0); // 20% range or at least 1.0
      dataRange = artificialRange;
      bottomValue = centerValue - dataRange / 2.0;
      topValue = centerValue + dataRange / 2.0;

      // Recalculate step based on this artificial range
      final double artificialStep = _calculateOptimalStepValue(dataRange, height);
      // Round bottom/top based on the new step
      bottomValue = (bottomValue / artificialStep).floor() * artificialStep;
      topValue = (topValue / artificialStep).ceil() * artificialStep;
      // Ensure at least one step difference
      if (topValue <= bottomValue + artificialStep * 0.5) {
        topValue = bottomValue + artificialStep;
      }
    } else {
      // Calculate optimal step based on the actual data range
      final double optimalStepValue = _calculateOptimalStepValue(dataRange, height);
      if (optimalStepValue <= 0) return; // Avoid division by zero

      // Calculate bottom/top by flooring/ceiling raw min/max to step value
      bottomValue = (rawMinValue / optimalStepValue).floor() * optimalStepValue;
      topValue = (rawMaxValue / optimalStepValue).ceil() * optimalStepValue;

      // Ensure bottom is actually below or equal to min
      while (bottomValue > rawMinValue - (optimalStepValue * 0.01)) { // Allow for small floating point errors
        bottomValue -= optimalStepValue;
      }
      // Ensure top is actually above or equal to max
      while (topValue < rawMaxValue + (optimalStepValue * 0.01)) { // Allow for small floating point errors
        topValue += optimalStepValue;
      }

      // Ensure we have at least one step between top and bottom
      if (topValue <= bottomValue + optimalStepValue * 0.5) {
        // If range collapses after rounding, add one step
        topValue = bottomValue + optimalStepValue;
      }
    }

    // Set the y-offset and calculate the scaling ratio
    valuesOffset = bottomValue;
    final double scaleValueRange = topValue - bottomValue;

    // Calculate the vertical ratio (pixels per value)
    verticalRatio = (scaleValueRange < 1e-10 || height <= 0) ? 1.0 : height / scaleValueRange;

    // --- Y Axis Label and Grid Line Drawing (Unchanged) ---
    // This part uses the calculated bottomValue, topValue, valuesOffset,
    // verticalRatio and optimalStepValue to draw labels and lines.
    final double stepForLabels = _calculateOptimalStepValue(scaleValueRange, height);
    if (stepForLabels <= 0) return;

    double currentYLabelValue = bottomValue;
    int stepsDrawnY = 0;
    while (currentYLabelValue <= topValue + (stepForLabels * 0.01) && stepsDrawnY < 100) {
      final double yPixelOffset = padding.top + height - ((currentYLabelValue - valuesOffset) * verticalRatio);

      if (yPixelOffset >= padding.top - 0.5 && yPixelOffset <= size.height - padding.bottom + 0.5) {
        // Draw horizontal grid line
        if (horizontalLinesPaint != null) {
          canvas.drawLine(
              Offset(padding.left, yPixelOffset),
              Offset(size.width - padding.right, yPixelOffset),
              horizontalLinesPaint!
          );
        }
        // Format and draw y-axis label
        String labelText;
        if (stepForLabels >= 1 || stepForLabels == 0) labelText = currentYLabelValue.toStringAsFixed(0);
        else if (stepForLabels >= 0.1) labelText = currentYLabelValue.toStringAsFixed(1);
        else if (stepForLabels >= 0.01) labelText = currentYLabelValue.toStringAsFixed(2);
        else labelText = currentYLabelValue.toStringAsExponential(1);

        final TextPainter textPainter = _getLabelTextPainter(labelText, horizontalLabelsTextStyle);
        textPainter.paint(
            canvas,
            Offset(padding.left - textPainter.width - 4, yPixelOffset - (textPainter.height / 2))
        );
      }
      currentYLabelValue += stepForLabels;
      // Handle potential floating point errors near the top
      if (currentYLabelValue > topValue && (currentYLabelValue - topValue).abs() < (stepForLabels * 0.01)) {
        currentYLabelValue = topValue;
      }
      stepsDrawnY++;
    }

    /* --- X Axis Setup (Unchanged) --- */
    double argumentsOffset = 0;
    final double xOffsetLimit = size.width - padding.right;
    double horizontalRatio = 1.0;

    if (argumentsLabels.isNotEmpty && arguments.isNotEmpty) {
      final double labelMinValueX = argumentsLabels.first.value;
      final double labelMaxValueX = argumentsLabels.last.value;
      final double dataMinValueX = arguments.first;
      final double dataMaxValueX = arguments.last;

      final double leftMostX = snapToLeftLabel ? math.min(dataMinValueX, labelMinValueX) : dataMinValueX;
      final double rightMostX = snapToRightLabel ? math.max(dataMaxValueX, labelMaxValueX) : dataMaxValueX;

      argumentsOffset = leftMostX;
      final double rangeX = rightMostX - leftMostX;

      final double fillWidthRatioX = (rangeX < 1e-9 || width <= 0) ? 1.0 : width / rangeX;
      horizontalRatio = math.max(_minimalHorizontalRatio, fillWidthRatioX);

      /* --- Draw X labels and grid lines (Unchanged) --- */
      for (LabelEntry tuple in argumentsLabels) {
        final double xValue = tuple.value;
        if (xValue < argumentsOffset) continue;
        final double xPixelOffset = padding.left + (xValue - argumentsOffset) * horizontalRatio;
        if (xPixelOffset > xOffsetLimit + 1) break;

        if (verticalLinesPaint != null) {
          canvas.drawLine(
              Offset(xPixelOffset, padding.top),
              Offset(xPixelOffset, size.height - padding.bottom),
              verticalLinesPaint!
          );
        }
        final TextPainter textPainter = _getLabelTextPainter(tuple.label, verticalLabelsTextStyle);
        textPainter.paint(
            canvas,
            Offset(xPixelOffset - textPainter.width / 2, size.height - padding.bottom + 4)
        );
      }
    } else {
      print("Warning: No arguments or argument labels provided for X axis.");
    }

    /* --- Data Series Points and Lines (Unchanged) --- */
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padding.left, padding.top, width, height));

    Iterator<Iterable<double>> seriesIterator = values.iterator;
    Iterator<Paint?> pointsPaintsIterator = seriesPointsPaints.iterator;
    Iterator<Paint>? linesPaintsIterator = (seriesLinesPaints ?? <Paint>[]).iterator;

    while (seriesIterator.moveNext()) {
      List<Offset> seriesPoints = [];
      Iterator<double> valueIterator = seriesIterator.current.iterator;
      Iterator<double> argumentIterator = arguments.iterator;

      Paint? currentLinePaint;
      if (seriesLinesPaints != null && linesPaintsIterator.moveNext()) {
        currentLinePaint = linesPaintsIterator.current;
      }
      Paint? currentPointPaint;
      if (pointsPaintsIterator.moveNext()) {
        currentPointPaint = pointsPaintsIterator.current;
      }

      while (valueIterator.moveNext() && argumentIterator.moveNext()) {
        final double currentArgumentX = argumentIterator.current;
        final double currentValueY = valueIterator.current;

        if (!currentValueY.isFinite || !currentArgumentX.isFinite) continue;
        if (currentArgumentX < argumentsOffset) continue; // Skip points before start

        final double xPixel = padding.left + (currentArgumentX - argumentsOffset) * horizontalRatio;
        if (xPixel > xOffsetLimit +1) break; // Skip points after end (+1 buffer)

        // Calculate y-coordinate using the final calculated offset and ratio
        final double yPixel = padding.top + height - ((currentValueY - valuesOffset) * verticalRatio);

        seriesPoints.add(Offset(xPixel, yPixel));
      }

      if (currentLinePaint != null && seriesPoints.length > 1) {
        final Path path = Path()..addPolygon(seriesPoints, false);
        canvas.drawPath(path, currentLinePaint);
      }
      if (currentPointPaint != null && seriesPoints.isNotEmpty) {
        canvas.drawPoints(ui.PointMode.points, seriesPoints, currentPointPaint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LineChartPainter old) {
    // Need to compare calculated min/max as they are used in paint logic now
    return (minValue != old.minValue ||
        maxValue != old.maxValue ||
        arguments != old.arguments ||
        values != old.values ||
        argumentsLabels != old.argumentsLabels ||
        seriesPointsPaints != old.seriesPointsPaints ||
        seriesLinesPaints != old.seriesLinesPaints ||
        horizontalLabelsTextStyle != old.horizontalLabelsTextStyle ||
        verticalLabelsTextStyle != old.verticalLabelsTextStyle ||
        padding != old.padding ||
        horizontalLinesPaint != old.horizontalLinesPaint ||
        verticalLinesPaint != old.verticalLinesPaint ||
        snapToLeftLabel != old.snapToLeftLabel ||
        snapToTopLabel != old.snapToTopLabel ||
        snapToRightLabel != old.snapToRightLabel ||
        snapToBottomLabel != old.snapToBottomLabel);
  }
}