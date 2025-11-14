// lib/res/Constants.dart
import 'package:flutter/material.dart';

class AppColor {
  static const duBlue = Color(0xFF004D94);
  static const bg = Color(0xfff6f6f6);
}

class AppConst {
  static const version = 'V 1.0.6';
}

/// 기기 식별용 간단 모델 (ConnectList에서 사용)
class DeviceKey {
  final String host;   // IP 또는 IP:PORT
  final int unitId;    // Modbus Unit ID
  final String name;   // 표시 이름

  const DeviceKey({
    required this.host,
    required this.unitId,
    required this.name,
  });

  String get id => '$host#$unitId';

  factory DeviceKey.fromJson(Map<String, dynamic> m) => DeviceKey(
    host: (m['host'] as String?) ?? '',
    unitId: (m['unitId'] as num?)?.toInt() ?? 1,
    name: (m['name'] as String?) ?? 'Device',
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'unitId': unitId,
    'name': name,
  };
}
