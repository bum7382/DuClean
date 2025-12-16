import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Provider 제거 (안씀)

import 'package:duclean/services/modbus_manager.dart';
// import 'package:duclean/providers/selected_device.dart'; // SelectedDevice 제거

class MotorScheduleService {
  MotorScheduleService._internal();
  static final MotorScheduleService _instance = MotorScheduleService._internal();
  factory MotorScheduleService() => _instance;

  // ---------- Prefs 키 ----------
  // [변경] 각 기기별 모터 주소(Run Register)를 저장하는 맵 (Key: "host_unitId", Value: address)
  static const _prefsKeyAddressMap = 'motor_schedule_address_map_v1';

  // [유지] 1회성 스케줄 실행 여부
  static const _prefsKeyFiredOnce = 'motor_schedule_fired_once_ids_v1';

  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _tickTimer;

  // [유지] init
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _startTickLoop();
  }

  // [유지] 타이머 로직
  void _startTickLoop() {
    if (_tickTimer != null) return;
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    final initialDelay = nextMinute.difference(now);

    Timer(initialDelay, () {
      _onTick();
      _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) => _onTick());
    });
  }

  // =========================================================
  // [UI 연동용] 기존 메서드 대체 및 보완
  // =========================================================

  /// [중요] UI에서 스케줄 저장할 때 사용할 Prefs Key를 만들어주는 함수
  /// 예: motor_schedules_192.168.0.10_1
  String getScheduleKey(String host, int unitId) {
    return 'motor_schedules_${host}_$unitId';
  }

  /// [중요] 스케줄 저장 시 UI에서 반드시 이 함수도 같이 호출해줘야 함
  /// 그래야 서비스가 "이 기기의 모터 주소(address)"를 기억하고 백그라운드에서 돌림
  Future<void> registerDeviceAddress(String host, int unitId, int address) async {
    final prefs = await SharedPreferences.getInstance();

    // 기존 맵 불러오기
    String jsonMap = prefs.getString(_prefsKeyAddressMap) ?? '{}';
    Map<String, dynamic> map = jsonDecode(jsonMap);

    // "host_unitId" 를 키로 주소 저장
    String key = '${host}_$unitId';
    map[key] = address;

    await prefs.setString(_prefsKeyAddressMap, jsonEncode(map));
  }

  /// 기존 setSchedule (호환용 - 이제 registerDeviceAddress를 감싸는 역할)
  void setSchedule({
    required String host,
    required int unitId,
    required int address,
    DateTime? onTime, DateTime? offTime, // 안 씀
    bool repeatOnWeekly = false, bool repeatOffWeekly = false, // 안 씀
  }) {
    registerDeviceAddress(host, unitId, address);
    _startTickLoop();
  }

  // =========================================================
  // [핵심] 1분마다 실행되는 로직 (다중 기기 순회로 변경)
  // =========================================================
  Future<void> _onTick() async {
    if (_navigatorKey == null) return;
    final ctx = _navigatorKey!.currentContext;
    if (ctx == null) return;

    final prefs = await SharedPreferences.getInstance();

    // 1. 등록된 기기들의 주소 맵 로드 ("host_unitId" : address)
    String jsonMap = prefs.getString(_prefsKeyAddressMap) ?? '{}';
    Map<String, dynamic> addressMap = {};
    try {
      addressMap = jsonDecode(jsonMap);
    } catch (_) {}

    if (addressMap.isEmpty) return;

    // 1회성 스케줄 실행 기록 로드
    final firedOnceStr = prefs.getString(_prefsKeyFiredOnce);
    Set<String> firedOnceIds = {};
    if (firedOnceStr != null) {
      try {
        firedOnceIds = (jsonDecode(firedOnceStr) as List).map((e) => e.toString()).toSet();
      } catch (_) {}
    }

    final now = DateTime.now();
    bool firedListChanged = false;

    // 2. 맵에 등록된 모든 기기를 순회하며 검사
    for (final key in addressMap.keys) {
      final parts = key.split('_');
      if (parts.length < 2) continue;

      final String host = parts[0];
      final int unitId = int.tryParse(parts[1]) ?? 1;
      final int address = addressMap[key] as int; // 모터 주소

      // 이 기기의 스케줄 리스트 로드 (키 생성 함수 사용)
      final String scheduleKey = getScheduleKey(host, unitId);
      final String? jsonStr = prefs.getString(scheduleKey);
      if (jsonStr == null || jsonStr.isEmpty) continue;

      List<dynamic> rawList = [];
      try {
        rawList = jsonDecode(jsonStr);
      } catch (_) { continue; }

      // 스케줄 루프
      for (final item in rawList) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();

        if (m['enabled'] == false) continue;

        // 시간 체크
        if (m['hour'] != now.hour || m['minute'] != now.minute) continue;

        // 요일 체크
        final List<dynamic> wdList = m['weekdays'] ?? [];
        final Set<int> weekdays = wdList.map((x) => x as int).toSet();
        final bool isOneShot = weekdays.isEmpty;

        // 1회용 중복 방지
        final String id = m['id'] ?? '';
        if (isOneShot && firedOnceIds.contains(id)) continue;
        if (!isOneShot && !weekdays.contains(now.weekday)) continue;

        // 실행
        final bool isOn = m['isOn'] as bool? ?? true;

        // ★ 중요: 순회 중인 host, unitId를 사용하여 실행
        await _fire(ctx, host, unitId, address, isOn);

        if (isOneShot) {
          firedOnceIds.add(id);
          firedListChanged = true;
        }
      }
    }

    if (firedListChanged) {
      await prefs.setString(_prefsKeyFiredOnce, jsonEncode(firedOnceIds.toList()));
    }
  }

  Future<void> _fire(BuildContext ctx, String host, int unitId, int address, bool turnOn) async {
    final desired = turnOn ? 1 : 0;
    final name = turnOn ? '스케줄ON' : '스케줄OFF';

    // [수정] SelectedDevice 체크 삭제 (백그라운드/다른화면 실행 보장)
    // [수정] readHolding 체크 삭제 (OFF 씹힘 방지)

    try {
      debugPrint('>>> 스케줄 실행 ($host): $name');

      // 무조건 쓰기
      await ModbusManager.instance.writeHolding(
        ctx,
        host: host,
        unitId: unitId,
        address: address,
        value: desired,
        name: name,
      );

    } catch (e) {
      debugPrint('스케줄 에러: $e');
    }
  }
}