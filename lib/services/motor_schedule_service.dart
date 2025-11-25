// lib/services/motor_schedule_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duclean/services/modbus_manager.dart';
import 'package:duclean/providers/selected_device.dart';

/// 모터 자동 스케줄 수행 서비스
///
/// - 일정 데이터는 SchedulePage 가 `motor_schedules_v1` 키로 저장한 것을 그대로 사용
///   (id, enabled, isOn, hour, minute, weekdays)
/// - 이 서비스는 매 분마다 SharedPreferences 를 읽어서
///   - enabled == true 이고
///   - (weekdays 비었거나, 오늘 요일이 포함돼 있고)
///   - 시간(hh:mm)이 현재 시간과 일치하는 항목에 대해
///   -> 모터 ON/OFF 명령을 수행한다.
/// - host / unitId / address 는 여전히 여기서 별도로 기억한다.
///   (어딘가에서 MotorScheduleService().setSchedule(...) 로 한 번 설정해줘야 함)
class MotorScheduleService {
  MotorScheduleService._internal();
  static final MotorScheduleService _instance = MotorScheduleService._internal();
  factory MotorScheduleService() => _instance;

  // ---------- Prefs 키들 ----------
  // 기기 정보 (어느 기기에 스케줄을 적용할지)
  static const _prefsKeyHost    = 'motor_schedule_host';
  static const _prefsKeyUnitId  = 'motor_schedule_unitId';
  static const _prefsKeyAddress = 'motor_schedule_address';

  // 일정 목록 (SchedulePage 에서 저장하는 키)
  static const _prefsKeySchedules = 'motor_schedules_v1';

  // 반복 없음(weekdays.isEmpty)인 일정 중, 이미 한 번 실행된 id 리스트
  static const _prefsKeyFiredOnce = 'motor_schedule_fired_once_ids_v1';

  GlobalKey<NavigatorState>? _navigatorKey;

  String? _host;
  int? _unitId;
  int? _address; // 모터 RUN 레지스터 주소

  Timer? _tickTimer;

  /// 앱 시작 시 main.dart 에서 호출:
  /// MotorScheduleService().init(navigatorKey);
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _restoreConfigAndStart(); // 비동기 복구 + 타이머 시작
  }

  /// 스케줄 전체 취소 + 저장 삭제
  void clearSchedule() {
    _tickTimer?.cancel();
    _tickTimer = null;

    _host = null;
    _unitId = null;
    _address = null;

    _removeConfigFromPrefs();
  }

  /// 기존 setSchedule API 유지 (호환용)
  ///
  /// 지금은 "언제 켤지/끌지"가 아니라
  /// "어느 기기(host/unitId/address)에 대해 스케줄을 수행할지" 설정하는 용도로만 사용.
  ///
  /// onTime / offTime / repeat* 는 더 이상 사용하지 않지만
  /// 시그니처는 그대로 두어서 기존 코드와 호환되게 함.
  void setSchedule({
    required String host,
    required int unitId,
    required int address,
    DateTime? onTime,
    DateTime? offTime,
    bool repeatOnWeekly = false,
    bool repeatOffWeekly = false,
  }) {
    _host = host;
    _unitId = unitId;
    _address = address;

    _saveConfigToPrefs();

    // 스케줄 루프가 돌고 있지 않다면 시작
    _startTickLoop();
  }

  // =========================================================
  // 내부 구현
  // =========================================================

  Future<void> _restoreConfigAndStart() async {
    final prefs = await SharedPreferences.getInstance();

    _host = prefs.getString(_prefsKeyHost);
    _unitId = prefs.getInt(_prefsKeyUnitId);
    _address = prefs.getInt(_prefsKeyAddress);

    // on/off 시간 관련 옛 키들은 더 이상 사용하지 않음

    // 타이머 시작 (host/unitId/address 가 null 이면 실제 동작은 안 함)
    _startTickLoop();
  }

  void _startTickLoop() {
    // 이미 돌고 있으면 그대로 사용
    if (_tickTimer != null) return;

    final now = DateTime.now();

    // 다음 분의 0초에 맞추기
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    final initialDelay = nextMinute.difference(now);

    // 처음 한 번은 nextMinute 에 맞춰 _onTick 실행,
    // 이후에는 1분마다 주기적으로 실행
    Timer(initialDelay, () {
      _onTick(); // 첫 실행

      _tickTimer = Timer.periodic(
        const Duration(minutes: 1),
            (_) => _onTick(),
      );
    });
  }

  Future<void> _saveConfigToPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    if (_host == null || _unitId == null || _address == null) {
      await _removeConfigFromPrefs();
      return;
    }

    await prefs.setString(_prefsKeyHost, _host!);
    await prefs.setInt(_prefsKeyUnitId, _unitId!);
    await prefs.setInt(_prefsKeyAddress, _address!);
  }

  Future<void> _removeConfigFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyHost);
    await prefs.remove(_prefsKeyUnitId);
    await prefs.remove(_prefsKeyAddress);
  }

  /// 1분마다 호출되는 실제 스케줄 체크 로직
  Future<void> _onTick() async {
    if (_navigatorKey == null) return;
    final ctx = _navigatorKey!.currentContext;
    if (ctx == null) return;

    // 스케줄을 수행할 기기 정보가 없으면 아무것도 안 함
    if (_host == null || _unitId == null || _address == null) {
      return;
    }

    // 현재 선택된 기기와 스케줄 대상 기기가 같은지 확인
    final selected = ctx.read<SelectedDevice>().current;
    if (selected == null ||
        selected.address != _host ||
        selected.unitId != _unitId) {
      // 선택된 기기가 다르면 실행하지 않음
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 일정 목록 로드
    final jsonStr = prefs.getString(_prefsKeySchedules);
    if (jsonStr == null || jsonStr.isEmpty) return;

    List<dynamic> rawList;
    try {
      rawList = jsonDecode(jsonStr) as List<dynamic>;
    } catch (e) {
      debugPrint('[MotorSchedule] 일정 목록 JSON 파싱 실패: $e');
      return;
    }
    if (rawList.isEmpty) return;

    // 이미 한 번 실행된 1회용 일정 id 목록 로드
    final firedOnceStr = prefs.getString(_prefsKeyFiredOnce);
    Set<String> firedOnceIds = {};
    if (firedOnceStr != null && firedOnceStr.isNotEmpty) {
      try {
        final list = jsonDecode(firedOnceStr) as List<dynamic>;
        firedOnceIds = list.map((e) => e.toString()).toSet();
      } catch (e) {
        debugPrint('[MotorSchedule] fired_once 목록 JSON 파싱 실패: $e');
      }
    }

    final now = DateTime.now();
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final currentWeekday = now.weekday; // 1=월 ... 7=일

    bool firedOnceListChanged = false;

    // 지금 시각에 해당하는 모든 일정에 대해 실행
    for (final item in rawList) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();

      final String id = m['id'] as String? ?? '';
      if (id.isEmpty) continue;

      final bool enabled = m['enabled'] as bool? ?? true;
      if (!enabled) continue;

      final int hour = m['hour'] as int? ?? 0;
      final int minute = m['minute'] as int? ?? 0;

      // 시각이 다르면 패스
      if (hour != currentHour || minute != currentMinute) {
        continue;
      }

      // 요일 체크
      final List<dynamic> wdListRaw =
          m['weekdays'] as List<dynamic>? ?? const [];
      final Set<int> weekdays =
      wdListRaw.map((x) => x as int).toSet();

      final bool isOneShot = weekdays.isEmpty;

      // 1회용 일정인데 이미 한 번 실행된 id 이면 무시
      if (isOneShot && firedOnceIds.contains(id)) {
        continue;
      }

      // 요일 지정된 일정이면, 오늘 요일이 없으면 패스
      if (!isOneShot && !weekdays.contains(currentWeekday)) {
        continue;
      }

      final bool isOn = m['isOn'] as bool? ?? true;

      // 이 시각에 조건을 만족하는 일정이면 실제 실행
      await _fire(turnOn: isOn);

      // 1회용 일정이면 실행 후 firedOnce에 기록
      if (isOneShot) {
        firedOnceIds.add(id);
        firedOnceListChanged = true;
      }
    }

    // firedOnce 목록이 변경됐으면 저장
    if (firedOnceListChanged) {
      try {
        final list = firedOnceIds.toList();
        await prefs.setString(_prefsKeyFiredOnce, jsonEncode(list));
      } catch (e) {
        debugPrint('[MotorSchedule] fired_once 목록 저장 실패: $e');
      }
    }
  }

  /// 실제 모터 ON/OFF 한 번 수행
  Future<void> _fire({required bool turnOn}) async {
    if (_navigatorKey == null) return;
    final ctx = _navigatorKey!.currentContext;
    if (ctx == null) return;

    if (_host == null || _unitId == null || _address == null) {
      return;
    }

    final host = _host!;
    final unitId = _unitId!;
    final address = _address!;
    final desired = turnOn ? 1 : 0;
    final name = turnOn ? '모터 ON(스케줄)' : '모터 OFF(스케줄)';

    // 1) 현재 선택된 기기가 맞는지 확인 (선택된 기기 아니면 아무 것도 안 함)
    final selected = ctx.read<SelectedDevice>().current;
    if (selected == null ||
        selected.address != host ||
        selected.unitId != unitId) {
      return;
    }

    try {
      // 2) 현재 상태 읽어서 이미 원하는 값이면 스킵
      final current = await ModbusManager.instance.readHolding(
        ctx,
        host: host,
        unitId: unitId,
        address: address,
        name: '자동 스케줄 상태 확인',
      );

      if (current == desired) {
        return;
      }

      // 3) 실제 쓰기
      final ok = await ModbusManager.instance.writeHolding(
        ctx,
        host: host,
        unitId: unitId,
        address: address,
        value: desired,
        name: name,
      );

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(ok ? '$name 자동 실행 완료' : '$name 자동 실행 실패'),
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('$name 자동 실행 오류: $e'),
        ),
      );
    } finally {
      // 기기 설정 상태만 다시 저장
      await _saveConfigToPrefs();
    }
  }
}
