// lib/providers/dp_history.dart
import 'package:flutter/foundation.dart';

class DpPoint {
  final DateTime time;
  final double value;

  DpPoint({
    required this.time,
    required this.value,
  });
}

class DpHistory extends ChangeNotifier {
  final List<DpPoint> _points = [];
  static const Duration window = Duration(minutes: 20);

  List<DpPoint> get points => List.unmodifiable(_points);

  void addPoint(double value) {
    final now = DateTime.now();

    // 직전 값과 같으면 추가하지 않음 (중복 방지)
    if (_points.isNotEmpty && _points.last.value == value) {
      _pruneOld(now);  // 오래된 값은 그래도 정리
      return;
    }

    _points.add(DpPoint(time: now, value: value));

    // 20분보다 오래된 데이터는 삭제
    _pruneOld(now);

    notifyListeners();
  }

  void _pruneOld(DateTime now) {
    while (_points.isNotEmpty &&
        _points.first.time.isBefore(now.subtract(window))) {
      _points.removeAt(0);
    }
  }

  void clear() {
    _points.clear();
    notifyListeners();
  }
}
