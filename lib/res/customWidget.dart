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
  final BoxBorder? border;

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
    this.border,
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
        border: border ?? null,
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
  final double? radius;
  final EdgeInsetsGeometry? padding;

  const BlueContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.linear,
    this.radius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? 20),
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
  final double? radius;
  final EdgeInsetsGeometry? padding;

  const GreenContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.linear,
    this.radius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? 20),
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
  final double? radius;

  const BgContainer({
    super.key,
    this.child,
    this.width,
    this.height,
    this.color,
    this.padding,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(radius ?? 30),
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
  final String title, unit;
  final double max, size, value;
  final double? thick;
  final Color? color;
  final bool isInt;
  final bool? portrait;

  const GaugeTile({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.max,
    required this.size,
    required this.isInt,
    this.thick,
    this.color,
    this.portrait,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: size * 0.12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.5,
                child: Container(
                  width: size,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: SfRadialGauge(
                      axes: <RadialAxis>[
                        RadialAxis(
                          startAngle: 180,
                          endAngle: 0,
                          minimum: 0,
                          maximum: max,
                          showLabels: false,
                          showTicks: false,
                          radiusFactor: 1,
                          axisLineStyle: AxisLineStyle(thickness: thick ?? size * 0.15),
                          pointers: <GaugePointer>[
                            RangePointer(
                                value: value,
                                color: color,
                                width: thick ?? size * 0.15,
                            ),
                          ],
                          annotations: <GaugeAnnotation>[
                            GaugeAnnotation(
                              angle: -90,
                              positionFactor: (portrait ?? true) ? size * 0.002 : size * 0.001,
                              widget: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isInt ? "${value.toInt()}" : "${value}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: size * 0.11,
                                      height: 0.5,
                                      color: color,
                                    ),
                                  ),
                                  Text(
                                    unit,
                                    style: TextStyle(
                                      fontSize: size * 0.09,
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
                ),
              ),
            )
          ],
        );
      },
    );
  }
}

class GaugeCircleTile extends StatelessWidget {

  final double? size, thick, value, max;
  final Color? color;
  final String? unit;
  final bool? isBlue;

  const GaugeCircleTile({
    super.key,
    required this.size,
    required this.thick,
    required this.value,
    required this.color,
    required this.unit,
    required this.max,
    this.isBlue,
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: SfRadialGauge(
          axes: <RadialAxis>[
            RadialAxis(
              showLabels: false,
              showTicks: false,
              startAngle: 270,
              endAngle: 270,
              radiusFactor: 1,
              maximum: max ?? 100,
              axisLineStyle: AxisLineStyle(
                thicknessUnit: GaugeSizeUnit.factor,
                thickness: thick ?? 0.2,
              ),
              annotations: <GaugeAnnotation>[
                GaugeAnnotation(
                  angle: 180,
                  widget: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "${value?.toInt()}",
                            style: TextStyle(
                              fontSize: size != null ? size! * 0.2 : 100,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            "$unit",
                            style: TextStyle(
                              fontSize: size != null ? size! * 0.11 : 100,
                              fontWeight: FontWeight.w300,
                              color: AppColor.duGrey,
                            ),
                          ),
                        ],
                      ),

                    ],
                  ),
                ),
              ],
              pointers: <GaugePointer>[
                RangePointer(
                  value: value ?? 0,
                  cornerStyle: CornerStyle.bothFlat,
                  enableAnimation: true,
                  animationDuration: 1200,
                  sizeUnit: GaugeSizeUnit.factor,
                  gradient: SweepGradient(
                    colors: (isBlue ?? true) ? <Color>[Color(0xFF0387D1), Color(0xFF0169B7)] : <Color>[Color(0xFF00BA77), Color(0xFF16AB5A)],
                    stops: <double>[0.25, 0.75],
                  ),
                  color: Color(0xFF00A8B5),
                  width: thick ?? 0.2,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
