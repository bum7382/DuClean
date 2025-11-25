// lib/res/Constants.dart
import 'package:flutter/material.dart';

class AppColor {
  // 일반 색
  static const bg = Color(0xFFFDFDFD);
  static const duBlue = Color(0xFF0168B6);
  static const duRed = Color(0xFFCF001F);
  static const duGreen = Color(0xFF16AB5A);
  static const duGrey = Color(0xFF6B7B95);
  static const duLightGrey = Color(0xFF889BB4);
  static const duBlack = Color(0xFF3A4A62);

  // 그라디언트 색
  static const duGreyGra  = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFF0F4F9),
      Color(0xFFE1E8F0),
    ],
  );

  static const duBlueGra  = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF157BC4),
      Color(0xFF0387D1),
    ],
  );

  static const duBlueGraLine  = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF157BC4),
      Color(0xFF0387D1),
    ],
  );

  static const duGreenGra  = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF16AB5A),
      Color(0xFF00BA77),
    ],
  );

  static const duGreenGraLine  = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF16AB5A),
      Color(0xFF00BA77),
    ],
  );

  static const duMixGra  = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF157BC4),
      Color(0xFF00BA77),
    ],
  );

  // 그림자 색
  static const duGreySha = <BoxShadow>[
    BoxShadow(
      color: Color(0x40000000),
      spreadRadius: -6,
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  static const duBlueSha = <BoxShadow>[
    BoxShadow(
      color: Color(0x99177AC2),
      spreadRadius: -6,
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  static const duGreenSha = <BoxShadow>[
    BoxShadow(
      color: Color(0x802BC735),
      spreadRadius: -6,
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];


}

class AppConst {
  static const version = 'V 1.0.9';
}

/// 기기 식별용 간단 모델 (ConnectList에서 사용)
class DeviceKey {
  final String host;   // IP 또는 IP:PORT
  final int unitId;    // Modbus Unit ID
  final String name;   // 표시 이름
  final int number;

  const DeviceKey({
    required this.host,
    required this.unitId,
    required this.name,
    this.number = 0,
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

/// 단일 일정 모델
class MotorScheduleEntry {
  final String id;          // 간단히 랜덤 문자열
  bool enabled;             // on/off 스위치
  bool isOn;                // true=켬, false=끔
  TimeOfDay time;           // 실행 시간
  Set<int> weekdays;        // 1(월) ~ 7(일)

  MotorScheduleEntry({
    required this.id,
    required this.enabled,
    required this.isOn,
    required this.time,
    required this.weekdays,
  });

  String get timeLabel {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get actionLabel => isOn ? '켬' : '끔';

  String get repeatLabel {
    if (weekdays.length == 7) return '매일';
    if (weekdays.isEmpty) return '반복 없음';
    final names = ['월', '화', '수', '목', '금', '토', '일'];

    return (weekdays.toList()..sort())
        .map((d) => names[d - 1])
        .join(', ');
  }


  MotorScheduleEntry copy() {
    return MotorScheduleEntry(
      id: id,
      enabled: enabled,
      isOn: isOn,
      time: time,
      weekdays: {...weekdays},
    );
  }
}
