import 'package:flutter/widgets.dart';

extension ContextMediaX on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  bool get isPortrait => MediaQuery.orientationOf(this) == Orientation.portrait;
}

/// 반응형 스케일 헬퍼.
///
/// 기준 폭 390(아이폰 14 기준)에 맞춰 디자인된 값을 현재 화면 폭에 비례해 반환.
/// 폰트는 너무 작아지거나 커지지 않도록 clamp 한다.
extension ContextScaleX on BuildContext {
  static const double _baseWidth = 390;
  static const double _fontMin = 0.85;
  static const double _fontMax = 1.30;

  double _ratio() => screenWidth / _baseWidth;

  /// 일반 사이징 (width, height, padding, radius 등).
  /// 예: `context.s(200)` → 기준 폭에서 200, 더 큰 화면에선 비례 증가.
  double s(double base) => base * _ratio();

  /// 폰트 사이즈 전용. 작은/큰 화면에서 가독성 깨지지 않게 clamp.
  double fs(double base) {
    final scaled = base * _ratio();
    return scaled.clamp(base * _fontMin, base * _fontMax);
  }

  /// 화면 폭 비율 (0.0 ~ 1.0). 기존 `w * 0.6` 패턴 대체용.
  double wp(double fraction) => screenWidth * fraction;

  /// 화면 높이 비율 (0.0 ~ 1.0).
  double hp(double fraction) => screenHeight * fraction;
}
