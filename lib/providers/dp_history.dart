import 'package:flutter/foundation.dart';

class DpPoint {
  final DateTime time;
  final double value;

  DpPoint({
    required this.time,
    required this.value,
  });
}

// 기기별 히스토리 묶음
class _DeviceDpHistory {
  final List<DpPoint> points = [];
  double? latestValue; // 초 단위 최신 값
}

class DpHistory extends ChangeNotifier {
  // key: 'host#unitId'
  final Map<String, _DeviceDpHistory> _store = {};
  static const Duration window = Duration(minutes: 60);

  String _key(String host, int unitId) => '$host#$unitId';

  _DeviceDpHistory _ensure(String host, int unitId) {
    final k = _key(host, unitId);
    return _store.putIfAbsent(k, () => _DeviceDpHistory());
  }

  /// 그래프용: 초당 1점, 기기별 저장
  /// 게이지용: 초단위 최신 값 유지
  void addPointFor(String host, int unitId, double value) {
    final now = DateTime.now();
    final dev = _ensure(host, unitId);

    // 게이지용: 항상 최신 값
    dev.latestValue = value;

    // 그래프용: 초 단위 타임스탬프
    final secondTs = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );

    if (dev.points.isEmpty) {
      dev.points.add(DpPoint(time: secondTs, value: value));
    } else {
      final last = dev.points.last;
      final lastSecondTs = DateTime(
        last.time.year,
        last.time.month,
        last.time.day,
        last.time.hour,
        last.time.minute,
        last.time.second,
      );

      // 새 초로 넘어갔을 때만 새 포인트 추가
      if (lastSecondTs.isBefore(secondTs)) {
        dev.points.add(DpPoint(time: secondTs, value: value));
      }
    }

    _pruneOldFor(dev, now);

    // 빌드 중 notify 경고 방지
    Future.microtask(() {
      notifyListeners();
    });
  }

  void _pruneOldFor(_DeviceDpHistory dev, DateTime now) {
    while (dev.points.isNotEmpty &&
        dev.points.first.time.isBefore(now.subtract(window))) {
      dev.points.removeAt(0);
    }
  }

  /// 특정 기기 히스토리 (그래프용, 초단위)
  List<DpPoint> pointsFor(String host, int unitId) {
    final dev = _store[_key(host, unitId)];
    if (dev == null) return const [];
    return List.unmodifiable(dev.points);
  }

  /// 특정 기기 최신 차압 값 (게이지용, 초단위)
  double latestDpFor(String host, int unitId) {
    final dev = _store[_key(host, unitId)];
    return dev?.latestValue ?? 0;
  }

  /// 필요하면 특정 기기만 초기화
  void clearFor(String host, int unitId) {
    _store.remove(_key(host, unitId));
    notifyListeners();
  }

  /// 전체 초기화
  void clearAll() {
    _store.clear();
    notifyListeners();
  }
}
