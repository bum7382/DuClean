import 'package:flutter/widgets.dart';

extension ContextMediaX on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  bool get isPortrait => MediaQuery.orientationOf(this) == Orientation.portrait;
}
