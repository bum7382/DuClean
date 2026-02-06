import 'dart:convert';

class AlarmRecord {
  final String host;
  final int unitId;
  final String name;
  final int code;
  final int tsMs;
  final int? clearedTsMs;

  const AlarmRecord({
    required this.host,
    required this.unitId,
    required this.name,
    required this.code,
    required this.tsMs,
    this.clearedTsMs,
  });

  // JSON 변환
  static AlarmRecord? fromJson(Map<String, dynamic> m) {
    final host = m['host'] as String?;
    final unitId = (m['unitId'] as num?)?.toInt();
    final name = m['name'] as String?;
    final code = (m['code'] as num?)?.toInt();
    final ts = (m['ts'] as num?)?.toInt();
    final cleared = (m['cleared_ts'] as num?)?.toInt();
    if (host == null || unitId == null || name == null || code == null || ts == null) return null;
    return AlarmRecord(host: host, unitId: unitId, name: name, code: code, tsMs: ts, clearedTsMs: cleared);
  }
}

class AlarmStore {
  static List<AlarmRecord> _memoryCache = [];

  static Future<List<AlarmRecord>> loadAllSortedDesc() async {
    // 최신순 정렬하여 반환
    _memoryCache.sort((a, b) => b.tsMs.compareTo(a.tsMs));
    return _memoryCache;
  }

  static Future<void> syncWithServer(List<Map<String, dynamic>> serverLogs, {String? defaultName}) async {
    final List<AlarmRecord> freshAlarms = [];

    for (var log in serverLogs) {
      final rawCode = log['status'] ?? log['code'];
      if (rawCode == null || rawCode.toString() == '0') continue;

      final int code = int.parse(rawCode.toString());
      final String host = (log['ip_address'] ?? '').toString().trim();
      final bool isActiveServer = log['active'] == true || log['active'].toString() == 'true';

      int tsMs;
      try {
        tsMs = DateTime.parse(log['timestamp']).millisecondsSinceEpoch;
      } catch(_) { tsMs = DateTime.now().millisecondsSinceEpoch; }

      int? stopTsMs;
      if (log['stop_timestamp'] != null) {
        try { stopTsMs = DateTime.parse(log['stop_timestamp']).millisecondsSinceEpoch; } catch(_) {}
      }

      freshAlarms.add(AlarmRecord(
        host: host,
        unitId: 1,
        name: defaultName ?? '기기',
        code: code,
        tsMs: tsMs,
        clearedTsMs: isActiveServer ? null : (stopTsMs ?? tsMs),
      ));
    }

    _memoryCache = freshAlarms;
  }

  static Future<void> clearAll() async {
    _memoryCache = [];
  }

  static Future<void> deleteByHost(String host) async {
    _memoryCache.removeWhere((e) => e.host == host);
  }

  static Future<void> appendOccurrence({
    required String host,
    required int unitId,
    required String name,
    required int code,
    required int tsMs,
  }) async {
    if (!_memoryCache.any((e) => e.host == host && e.code == code && e.clearedTsMs == null)) {
      _memoryCache.add(AlarmRecord(host: host, unitId: unitId, name: name, code: code, tsMs: tsMs));
    }
  }

  static Future<void> appendClear({
    required String host,
    required int unitId,
    required int code,
    required int clearedAtMs,
  }) async {
    for (var i = _memoryCache.length - 1; i >= 0; i--) {
      final e = _memoryCache[i];
      if (e.host == host && e.unitId == unitId && e.code == code && e.clearedTsMs == null) {
        _memoryCache[i] = AlarmRecord(
          host: e.host, unitId: e.unitId, name: e.name,
          code: e.code, tsMs: e.tsMs, clearedTsMs: clearedAtMs,
        );
        return;
      }
    }
  }
}