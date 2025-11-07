// lib/providers/Providers.dart
// 목적: 기기별(IP, Unit ID, 연결 상태)을 provider로 관리 + SharedPreferences에 영구 저장.
// - 최소 필드만 사용: name, ip, unitId, connected
// - 각 setter가 호출될 때마다 즉시 저장(_save) + UI 갱신(notifyListeners)

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences에 저장할 때 사용할 키(문자열 한 개면 충분).
/// - "어디에 저장하냐"를 가리키는 이름표라고 생각하면 됨.
/// - 앱 전체에서 재사용하므로 상수로 분리.
const String _kPrefsKey = 'duclean_device_registry_v1';

/// 단일 기기의 상태 모델
class DeviceInfo {
  String name;     // 기기명(고유키, 예: "AP-500")
  String ip;       // IP 주소
  int unitId;      // Unit ID
  bool connected;  // 연결 상태

  DeviceInfo({
    required this.name,
    this.ip = '',
    this.unitId = 0,
    this.connected = false,
  });

  /// 저장/전송을 위한 JSON 변환
  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'unitId': unitId,
    'connected': connected,
  };

  /// JSON → 객체
  static DeviceInfo fromJson(Map<String, dynamic> m) => DeviceInfo(
    name: m['name'] as String,
    ip: (m['ip'] as String?) ?? '',
    unitId: (m['unitId'] as num?)?.toInt() ?? 0,
    connected: (m['connected'] as bool?) ?? false,
  );
}

/// 레지스트리: 기기명(name) → DeviceInfo
/// - ChangeNotifier를 상속해 UI가 변경을 구독할 수 있게 함.
class DeviceRegistry extends ChangeNotifier {
  final Map<String, DeviceInfo> _map = {};

  /// 전체 기기 리스트(정렬은 화면에서 필요 시 수행)
  List<DeviceInfo> get devices => _map.values.toList();

  /// 단일 기기 조회(없으면 null)
  DeviceInfo? getByName(String name) => _map[name];

  /// 없으면 생성해서 반환(간편한 set 계열에서 사용)
  DeviceInfo _getOrCreate(String name) =>
      _map[name] ??= DeviceInfo(name: name);

  // ---------------------------
  // 영구 저장/불러오기
  // ---------------------------

  /// 앱 시작 시 호출해서 SharedPreferences → 메모리로 로드
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return; // 저장된 데이터가 아직 없음

    try {
      final List<dynamic> decoded = jsonDecode(raw);
      _map
        ..clear()
        ..addEntries(decoded
            .whereType<Map<String, dynamic>>()
            .map(DeviceInfo.fromJson)
            .map((d) => MapEntry(d.name, d)));
      notifyListeners(); // 로드 완료 → 화면 갱신
    } catch (_) {
      // 손상된 데이터 등은 무시(필요시 초기화)
    }
  }

  /// 현재 메모리 상태를 SharedPreferences에 저장
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _map.values.map((e) => e.toJson()).toList();
    await prefs.setString(_kPrefsKey, jsonEncode(list));
  }

  // ---------------------------
  // 갱신 API (저장 + 화면갱신)
  // ---------------------------

  /// IP 설정
  Future<void> setIp(String name, String ip) async {
    _getOrCreate(name).ip = ip;
    await _save();
    notifyListeners();
  }

  /// Unit ID 설정
  Future<void> setUnitId(String name, int unitId) async {
    _getOrCreate(name).unitId = unitId;
    await _save();
    notifyListeners();
  }

  /// 연결 상태 설정(연결/끊김 콜백에서 사용)
  Future<void> setConnected(String name, bool connected) async {
    _getOrCreate(name).connected = connected;
    await _save();
    notifyListeners();
  }

  /// 여러 필드를 한 번에 부분 업데이트
  Future<void> upsert({
    required String name,
    String? ip,
    int? unitId,
    bool? connected,
  }) async {
    final d = _getOrCreate(name);
    if (ip != null) d.ip = ip;
    if (unitId != null) d.unitId = unitId;
    if (connected != null) d.connected = connected;
    await _save();
    notifyListeners();
  }

  /// 단일 기기 삭제
  Future<void> remove(String name) async {
    _map.remove(name);
    await _save();
    notifyListeners();
  }

  /// 전체 초기화
  Future<void> clear() async {
    _map.clear();
    await _save();
    notifyListeners();
  }
}
