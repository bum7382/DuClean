import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import 'package:flutter/material.dart';

class RoundContainer extends StatelessWidget {

  final Widget? child;
  final Color? color;
  final double? width;
  final double? height;
  final double? borderRadius;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final EdgeInsetsGeometry? padding;

  const RoundContainer({
    super.key,
    this.child,
    this.color,
    this.width,
    this.height,
    this.borderRadius,
    this.gradient,
    this.shadow,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius ?? 0),
        gradient: gradient,
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}

class BlueContainer extends StatelessWidget {

  final Widget? child;
  final double? width;
  final double? height;
  final bool? linear;
  final EdgeInsetsGeometry? padding;

  const BlueContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.linear,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: (linear ?? false) ? AppColor.duBlueGraLine : AppColor.duBlueGra,
        boxShadow: AppColor.duBlueSha,
      ),
      child: child,
    );
  }
}

class GreenContainer extends StatelessWidget {

  final Widget? child;
  final double? width;
  final double? height;
  final bool? linear;
  final EdgeInsetsGeometry? padding;

  const GreenContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.linear,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: (linear ?? false) ? AppColor.duGreenGraLine : AppColor.duGreenGra,
        boxShadow: AppColor.duGreenSha,
      ),
      child: child,
    );
  }
}

class TransContainer extends StatelessWidget {

  final Widget? child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  const TransContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: Color(0x4DFFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          width: 0.5,
          color: Colors.white,
        )
      ),
      child: child,
    );
  }
}

class BgContainer extends StatelessWidget {

  final Widget? child;
  final double? width;
  final double? height;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  const BgContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.color,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: AppColor.duGreySha,
        border: Border.all(
          color: Color(0x80E0E2E6),
          width: 0.3,
          strokeAlign: BorderSide.strokeAlignOutside
        )
      ),
      child: child,
    );
  }
}

class GaugeTile extends StatelessWidget {
  const GaugeTile({
    super.key,
    required this.title,
    required this.valueStr,
    required this.unit,
    required this.max,
    required this.size,
    required this.color,
  });

  final String title, valueStr, unit;
  final double max, size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(valueStr) ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = size * 0.8;
        final axis = size * 0.13;
        final titleFont = size * 0.10;
        final valueFont = size * 0.10;
        final unitFont = size * 0.075;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: titleFont,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            SizedBox(
              height: h,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    startAngle: 180,
                    endAngle: 0,
                    minimum: 0,
                    maximum: max,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: AxisLineStyle(thickness: axis),
                    pointers: <GaugePointer>[
                      RangePointer(value: value, color: color, width: axis),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        angle: -90,
                        positionFactor: 0.1,
                        widget: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              valueStr,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: valueFont,
                                color: color,
                              ),
                            ),
                            Text(
                              unit,
                              style: TextStyle(
                                fontSize: unitFont,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
