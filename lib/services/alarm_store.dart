import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'package:duclean/res/Constants.dart'; // 필요 시 사용
// import 'package:material_symbols_icons/symbols.dart'; // 필요 시 사용
// import 'package:duclean/res/settingWidget.dart'; // 필요 시 사용

const String kAlarmHistKey = 'alarm_history_v2';

class AlarmRecord {
  final String host;
  final int unitId;
  final String name;     // 표시용 기기명
  final int code;        // 1~7
  final int tsMs;        // 발생 시각
  final int? clearedTsMs;

  const AlarmRecord({
    required this.host,
    required this.unitId,
    required this.name,
    required this.code,
    required this.tsMs,
    this.clearedTsMs,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'unitId': unitId,
    'name': name,
    'code': code,
    'ts': tsMs,
    if (clearedTsMs != null) 'cleared_ts': clearedTsMs,
  };

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
  static const int _maxKeep = 1000;

  static Future<List<AlarmRecord>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kAlarmHistKey) ?? const <String>[];
    final out = <AlarmRecord>[];
    for (final s in raw) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final rec = AlarmRecord.fromJson(m);
        if (rec != null) out.add(rec);
      } catch (_) {}
    }
    return out;
  }

  // 알람 기록 전체 삭제
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAlarmHistKey);
  }

  // [추가됨] 특정 호스트의 알람만 삭제
  static Future<void> deleteByHost(String host) async {
    // 1. 전체 로드
    final all = await _loadRaw();

    // 2. 해당 host가 아닌 것들만 남김 (필터링)
    final kept = all.where((e) => e.host != host).toList();

    // 3. 남은 것들로 다시 저장
    await _saveAll(kept);
  }

  static Future<void> _saveAll(List<AlarmRecord> list) async {
    final prefs = await SharedPreferences.getInstance();
    // 오래된 것 정리
    list.sort((a, b) => a.tsMs.compareTo(b.tsMs));
    if (list.length > _maxKeep) {
      list.removeRange(0, list.length - _maxKeep);
    }
    final encoded = list.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(kAlarmHistKey, encoded);
  }

  /// 알람 발생 기록 추가(중복 방지: 동일 device+code+ts 존재 시 skip)
  static Future<void> appendOccurrence({
    required String host,
    required int unitId,
    required String name,
    required int code,
    required int tsMs,
  }) async {
    final all = await _loadRaw();
    final dup = all.any((e) => e.host == host && e.unitId == unitId && e.code == code && e.tsMs == tsMs);
    if (!dup) {
      all.add(AlarmRecord(host: host, unitId: unitId, name: name, code: code, tsMs: tsMs));
      await _saveAll(all);
    }
  }

  /// 알람 해제 기록 병합(해제 시각만 업데이트)
  static Future<void> appendClear({
    required String host,
    required int unitId,
    required int code,
    required int clearedAtMs,
  }) async {
    final all = await _loadRaw();
    // 미해제 중 최신 같은 code를 우선 해제
    for (var i = all.length - 1; i >= 0; i--) {
      final e = all[i];
      if (e.host == host && e.unitId == unitId && e.code == code && e.clearedTsMs == null) {
        all[i] = AlarmRecord(
          host: e.host, unitId: e.unitId, name: e.name,
          code: e.code, tsMs: e.tsMs, clearedTsMs: clearedAtMs,
        );
        await _saveAll(all);
        return;
      }
    }
  }

  static Future<List<AlarmRecord>> loadAllSortedDesc() async {
    final all = await _loadRaw();
    all.sort((a, b) => b.tsMs.compareTo(a.tsMs));
    return all;
  }

  // services/alarm_store.dart 내 syncWithServer 메서드 수정

  static Future<void> syncWithServer(List<Map<String, dynamic>> serverLogs, {String? defaultName}) async {
    final List<AlarmRecord> all = await _loadRaw();
    bool isChanged = false;

    for (var log in serverLogs) {
      final rawCode = log['status'] ?? log['code'];
      if (rawCode == null || rawCode.toString() == '0') continue;

      final int code = int.parse(rawCode.toString());
      final String host = (log['ip_address'] ?? '').toString().trim();
      final bool isActiveServer = log['active'] == true || log['active'].toString() == 'true';
      final int tsMs = DateTime.parse(log['timestamp']).millisecondsSinceEpoch;
      final int? stopTsMs = log['stop_timestamp'] != null
          ? DateTime.parse(log['stop_timestamp']).millisecondsSinceEpoch
          : null;

      // [중복 체크 강화] 동일 호스트 + 동일 코드 + 시간 차이가 2초(2000ms) 이내인 데이터 찾기
      int idx = all.indexWhere((e) =>
      e.host == host &&
          e.code == code &&
          (e.tsMs - tsMs).abs() < 2000 // 2초 이내 오차는 같은 알람으로 간주
      );

      if (idx != -1) {
        // 1. 이미 존재한다면 서버 데이터 기준으로 상태만 업데이트 (무결성 보장)
        final local = all[idx];
        if (isActiveServer != (local.clearedTsMs == null)) {
          all[idx] = AlarmRecord(
            host: local.host,
            unitId: local.unitId,
            name: defaultName ?? local.name,
            code: local.code,
            tsMs: local.tsMs, // 로컬 시간 유지 (중복 생성 방지)
            clearedTsMs: isActiveServer ? null : (stopTsMs ?? tsMs),
          );
          isChanged = true;
        }
      } else {
        // 2. 아예 새로운 데이터라면 추가
        all.add(AlarmRecord(
          host: host,
          unitId: 1,
          name: defaultName ?? 'Unknown',
          code: code,
          tsMs: tsMs,
          clearedTsMs: isActiveServer ? null : (stopTsMs ?? tsMs),
        ));
        isChanged = true;
      }
    }

    if (isChanged) await _saveAll(all);
  }
}