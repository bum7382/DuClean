// lib/res/Constants.dart
import 'package:flutter/material.dart';
import 'package:duclean/common/context_extensions.dart';

/// 간격 토큰. 모든 padding/margin/SizedBox 값은 여기서 가져다 쓴다.
/// 화면 폭에 비례한 값이 필요하면 [AppSpacing.r] 사용.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// 반응형 간격. `AppSpacing.r(context, AppSpacing.md)` 형태.
  static double r(BuildContext c, double base) => c.s(base);
}

/// 둥근 모서리 토큰.
class AppRadius {
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 30;
  static const double pill = 100;
}

/// 폰트 사이즈 토큰. 모두 "기준 폭(390) 기준의 px"이며,
/// 실제 사용 시에는 [AppText] 헬퍼나 `context.fs(...)`로 감싸 적용한다.
class AppFontSize {
  static const double caption = 11;
  static const double small = 13;
  static const double body = 14;
  static const double subtitle = 16;
  static const double title = 20;
  static const double headline = 24;
  static const double display = 32;
  static const double hero = 40;
}

/// 자주 쓰는 텍스트 스타일 프리셋. 폰트 크기는 화면에 맞춰 자동 스케일.
/// 색/굵기는 호출부에서 `.copyWith(...)`로 덮어쓸 것.
class AppText {
  static TextStyle caption(BuildContext c) =>
      TextStyle(fontSize: c.fs(AppFontSize.caption));
  static TextStyle small(BuildContext c) =>
      TextStyle(fontSize: c.fs(AppFontSize.small));
  static TextStyle body(BuildContext c) =>
      TextStyle(fontSize: c.fs(AppFontSize.body));
  static TextStyle subtitle(BuildContext c) => TextStyle(
        fontSize: c.fs(AppFontSize.subtitle),
        fontWeight: FontWeight.w500,
      );
  static TextStyle title(BuildContext c) => TextStyle(
        fontSize: c.fs(AppFontSize.title),
        fontWeight: FontWeight.w600,
      );
  static TextStyle headline(BuildContext c) => TextStyle(
        fontSize: c.fs(AppFontSize.headline),
        fontWeight: FontWeight.w700,
      );
  static TextStyle display(BuildContext c) => TextStyle(
        fontSize: c.fs(AppFontSize.display),
        fontWeight: FontWeight.w700,
      );
  static TextStyle hero(BuildContext c) => TextStyle(
        fontSize: c.fs(AppFontSize.hero),
        fontWeight: FontWeight.w700,
      );
}

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
  static const version = 'V 1.1.8';
}

/// 기기 식별용 간단 모델 (ConnectList에서 사용)
class DeviceKey {
  final String host;       // IP
  final int unitId;        // Modbus Unit ID
  final String name;       // 표시 이름
  final int number;        // 정렬 순서 (저장 필요)
  final String macAddress; // [추가] 고유 식별자 (DB 조회용)
  final String serial;

  const DeviceKey({
    required this.host,
    required this.unitId,
    required this.name,
    this.number = 0,
    this.macAddress = '',
    required this.serial,
  });

  String get id => '$host#$unitId';

  factory DeviceKey.fromJson(Map<String, dynamic> m) => DeviceKey(
    host: (m['host'] as String?) ?? '',
    unitId: (m['unitId'] as num?)?.toInt() ?? 1,
    name: (m['name'] as String?) ?? 'Device',
    number: (m['number'] as num?)?.toInt() ?? 0, // [수정] 순서 저장 복구
    macAddress: (m['macAddress'] as String?) ?? '', // [추가] MAC 주소 로드
    serial: m['serial'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'unitId': unitId,
    'name': name,
    'number': number,       // [수정] 순서 저장
    'macAddress': macAddress, // [추가] MAC 주소 저장
    'serial': serial,
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
