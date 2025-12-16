import 'package:flutter/foundation.dart';
import '../models/device_info.dart';
import 'package:flutter/scheduler.dart';

// 현재 선택된 기기 정보
class SelectedDevice extends ChangeNotifier {
  DeviceInfo? _current; // 현재 선택된 기기
  DeviceInfo? get current => _current;  // 읽기
  bool get hasSelection => _current != null;  // 선택 여부 체크

  // 기기 선택
  void select(DeviceInfo info) {
    if (_current == info) return;
    _current = info;
    notifyListeners();  // 리빌드
  }

  // 선택 해제
  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}

// 기기 상태
class ConnState {
  bool connected;        // 현재 연결 여부
  int? alarmCode;        // 알람 코드(0~7)
  DateTime? alarmAt;     // 알람 코드 변경 시각 (발생/해제 시각 모두 포함)
  DateTime? lastClearedAt; // 마지막 해제 시각(N→0)
  int? lastClearedCode;    // 마지막으로 해제된 코드(N)
  DateTime? lastClearedSourceAt; // 그 알람이 발생했던 시각
  DateTime? lastSeen;    // 마지막 통신 성공 시각
  int failCount;         // 연속 실패 횟수(백오프/표시)

  ConnState({
    this.connected = false,
    this.alarmCode,
    this.alarmAt,
    this.lastClearedAt,
    this.lastClearedCode,
    this.lastClearedSourceAt,
    this.lastSeen,
    this.failCount = 0,
  });
}

// 장비 키, host+unitId로 유일 식별
class DeviceKeyLite {
  final String host;   // IP
  final int unitId;    // Unit ID
  final String id;     // host#unitId
  DeviceKeyLite({required this.host, required this.unitId}) : id = '$host#$unitId';
}

// 연결 기기 + 알람 코드/발생시각 관리
class ConnectionRegistry extends ChangeNotifier {
  // key: 'host#unitId'  value: ConnState
  final Map<String, ConnState> _states = {};
  Map<String, ConnState> get states => _states;

  void _safeNotifyListeners() {
    // foundation.dart 에서 SchedulerBinding 가져오려면
    if (!SchedulerBinding.instance.hasScheduledFrame &&
        SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      // 지금 빌드/레이아웃/페인트 중이 아니면 바로
      notifyListeners();
    } else {
      // 빌드 중/레이아웃 중이면 다음 프레임으로 미룸
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  // 해당 장비의 상태를 가져옴, 없으면 생성
  ConnState stateOf(String host, int unitId) =>
      _states.putIfAbsent('${host}#${unitId}', () => ConnState());

  // 연결된 장비 목록
  List<DeviceKeyLite> get connectedDevices => _states.entries
      .where((e) => e.value.connected)
      .map((e) {
    final parts = e.key.split('#'); // ['host','unitId']
    return DeviceKeyLite(host: parts[0], unitId: int.parse(parts[1]));
  }).toList();

  // 연결 표시
  void markConnected(String host, int unitId) {
    final s = stateOf(host, unitId);
    s.connected = true;
    s.lastSeen = DateTime.now();
    s.failCount = 0;
    _safeNotifyListeners();
  }

  // 연결 해제 표시
  void markDisconnected(String host, int unitId) {
    final s = stateOf(host, unitId);
    s.connected = false;
    _safeNotifyListeners();
  }

  // 알람 코드 변경 시 alarmAt을 갱신
  void setAlarmCode(String host, int unitId, int code, {DateTime? at}) {
    final s = stateOf(host, unitId);

    int cur = code;

    final now = at ?? DateTime.now();
    final prev = s.alarmCode ?? 0;

    if (cur != 0 && prev != cur) {
      // 새 알람 발생 (0→N 또는 N→M)
      s.alarmCode = cur;
      s.alarmAt = now; // 발생 시각
      s.lastSeen = now;
      _safeNotifyListeners();
      return;
    }

    if (cur == 0) {
      // 해제(N→0)
      if (prev != 0) {
        s.lastClearedCode = prev;
        s.lastClearedAt = now;
        s.lastClearedSourceAt = s.alarmAt; // 발생 시각 스냅샷
      }
      s.alarmCode = 0;
      s.lastSeen = now;
      _safeNotifyListeners();
      return;
    }

    // 변경 없음 → 헬스만 갱신
    s.lastSeen = now;
  }

  /// 실패 누적(타임아웃/에러 처리 시)
  void bumpFail(String host, int unitId) {
    final s = stateOf(host, unitId);
    s.failCount += 1;
    _safeNotifyListeners();
  }
}
