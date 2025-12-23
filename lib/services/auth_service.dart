import 'package:flutter/material.dart';
import 'package:duclean/services/modbus_manager.dart';

/// 각 기기별로 가질 권한 상태 클래스
class DevicePermissions {
  bool isUserMode = false;
  bool isAdminMode = false;
}

class AuthService extends ChangeNotifier {
  // 1. 장비 암호 인증 상태 (기존 유지)
  final Map<String, bool> _authorizedDevices = {};

  // 2. ⭐ 기기별 사용자/관리자 권한 상태 (Key: "host:unitId")
  final Map<String, DevicePermissions> _permissionsMap = {};

  /// 기기 고유 키 생성 헬퍼
  String _makeKey(String? host, int? unitId) => '$host:$unitId';

  /// 특정 기기의 권한 객체를 가져오거나 없으면 생성 (내부용)
  DevicePermissions _getPerms(String? host, int? unitId) {
    final key = _makeKey(host, unitId);
    return _permissionsMap.putIfAbsent(key, () => DevicePermissions());
  }

  // --- [외부 참조용 Getter 함수들] ---

  /// 특정 기기의 사용자 권한 여부 확인
  bool isUserMode(String? host, int? unitId) {
    if (host == null || unitId == null) return false;
    return _getPerms(host, unitId).isUserMode;
  }

  /// 특정 기기의 관리자 권한 여부 확인
  bool isAdminMode(String? host, int? unitId) {
    if (host == null || unitId == null) return false;
    return _getPerms(host, unitId).isAdminMode;
  }

  /// 특정 기기의 장비 암호 인증 여부 확인
  bool isAuthorized(String? host, int? unitId) {
    if (host == null || unitId == null) return false;
    return _authorizedDevices[_makeKey(host, unitId)] ?? false;
  }

  // --- [상태 변경 함수들] ---

  /// 특정 기기의 사용자 권한 설정
  void setUserMode(String host, int unitId, bool value) {
    final p = _getPerms(host, unitId);
    p.isUserMode = value;
    // 사용자 권한 해제 시 관리자 권한도 강제 해제
    if (!value) p.isAdminMode = false;
    notifyListeners();
  }

  /// 특정 기기의 관리자 권한 설정
  void setAdminMode(String host, int unitId, bool value) {
    final p = _getPerms(host, unitId);
    p.isAdminMode = value;
    notifyListeners();
  }

  /// 인증 상태 초기화 (기기 변경 시 혹은 로그아웃 시)
  void resetAuth(String host, int unitId) {
    final key = _makeKey(host, unitId);
    _authorizedDevices.remove(key);
    _permissionsMap.remove(key);
    notifyListeners();
  }

  // --- [장비 통신 인증] ---

  /// 장비의 40048번지 값과 입력값 비교
  Future<bool> checkDevicePassword(BuildContext context, {
    required String host,
    required int unitId,
    required String name,
    required String input,
  }) async {
    try {
      final int? devicePass = await ModbusManager.instance.readHolding(
          context, host: host, unitId: unitId, address: 47, name: name
      );

      if (devicePass != null && input == devicePass.toString()) {
        _authorizedDevices[_makeKey(host, unitId)] = true;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    }
    return false;
  }
}