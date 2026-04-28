import 'package:flutter/foundation.dart';

/// 각 기기별로 가질 권한 상태 클래스
class DevicePermissions {
  bool isUserMode = false;
  bool isAdminMode = false;
}

class AuthService extends ChangeNotifier {
  // 기기별 사용자/관리자 권한 상태 (Key: "host:unitId")
  final Map<String, DevicePermissions> _permissionsMap = {};

  String _makeKey(String? host, int? unitId) => '$host:$unitId';

  DevicePermissions _getPerms(String? host, int? unitId) {
    final key = _makeKey(host, unitId);
    return _permissionsMap.putIfAbsent(key, () => DevicePermissions());
  }

  bool isUserMode(String? host, int? unitId) {
    if (host == null || unitId == null) return false;
    return _getPerms(host, unitId).isUserMode;
  }

  bool isAdminMode(String? host, int? unitId) {
    if (host == null || unitId == null) return false;
    return _getPerms(host, unitId).isAdminMode;
  }

  void setUserMode(String host, int unitId, bool value) {
    final p = _getPerms(host, unitId);
    p.isUserMode = value;
    // 사용자 권한 해제 시 관리자 권한도 강제 해제
    if (!value) p.isAdminMode = false;
    notifyListeners();
  }

  void setAdminMode(String host, int unitId, bool value) {
    final p = _getPerms(host, unitId);
    p.isAdminMode = value;
    notifyListeners();
  }
}
