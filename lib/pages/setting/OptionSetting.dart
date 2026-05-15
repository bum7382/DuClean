import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:duclean/services/modbus_manager.dart';


class OptionSettingPage extends StatefulWidget {
  const OptionSettingPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
    this.onRunModeChanged,
    required this.host,
    required this.unitId,
    required this.name,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;
  final void Function(String)? onRunModeChanged;
  final String host;
  final int unitId;
  final String name;

  @override
  State<OptionSettingPage> createState() => _OptionSettingPageState();
}

class _OptionSettingPageState extends State<OptionSettingPage> {
  static const List<String> _labels = ['판넬', '연동', '원격', '통신(RS485)'];
  static const List<String> _labels_buzzer = ['음소거', 'ON', '자동'];
  // 40075: 1=시스템설정, 2=운전설정
  static const List<String> _labels_pwMenu = ['시스템설정', '운전설정'];
  String? runMode;  // 운전 모드
  bool? stopShowDp;  // 운전 정지 시 차압 표시
  bool? overDpFan;  // 과차압 팬작동
  bool? multiContact; // 다기능 접점
  bool? blackoutReward; // 정전 보상
  bool? linkContactMisPrevent;  // 연동 접점 오동작 방지
  String? buzzerMode; // 부저모드
  String? pwEntryMenu; // 암호 진입 메뉴 설정 (1: 시스템설정, 2: 운전설정)

  bool _loadFailed = false;          // 모든 시도 실패 여부
  static const int _maxRetry = 10;

  @override
  void initState() {
    super.initState();
    _loadInitialSettings();
  }

  Future<void> _loadInitialSettings() async {
    _loadFailed = false;

    setState(() {
      runMode = null;
      stopShowDp = null;
      overDpFan = null;
      multiContact = null;
      blackoutReward = null;
      linkContactMisPrevent = null;
      buzzerMode = null;
      pwEntryMenu = null;
    });
    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        // 디바이스가 큰 패킷(count>=49)을 제대로 못 채우는 quirk 가 있어 두 번에 나눠 읽음
        // 1차: 26~70 (count 45 - Main 과 동일, 검증된 크기)
        final List<int>? r1 = await ModbusManager.instance.readHoldingRange(
          context,
          host: widget.host,
          unitId: widget.unitId,
          startAddress: 26,
          count: 45,
          name: 'OperationSettings(1)',
        );
        // 2차: 71~74 (신규 레지스터)
        final List<int>? r2 = await ModbusManager.instance.readHoldingRange(
          context,
          host: widget.host,
          unitId: widget.unitId,
          startAddress: 71,
          count: 4,
          name: 'OperationSettings(2)',
        );
        if (r1 != null && r1.length >= 45 && r2 != null && r2.length >= 4) {
          if (!mounted) return;
          setState(() {
            // r1: index = addr - 26
            final int modeVal    = r1[8];   // 34
            final int blackReVal = r1[9];   // 35
            final int multiCVal  = r1[10];  // 36
            final int overDpVal  = r1[31];  // 57
            final int stopShVal  = r1[44];  // 70
            // r2: index = addr - 71
            final int linkCMisPrevVal = r2[0]; // 71
            final int buzzerModeVal   = r2[1]; // 72
            final int pwMenuVal       = r2[3]; // 74

            // 1. 운전 모드 설정 (라벨 매핑)
            final m = modeVal;
            final safeIndex = (m >= 0 && m < _labels.length) ? m : 0;
            runMode = _labels[safeIndex];

            // 2. 부저 모드 설정
            final n = buzzerModeVal;
            final buzzerSafeIndex = (n >= 0 && n < _labels_buzzer.length) ? n : 0;
            buzzerMode = _labels_buzzer[buzzerSafeIndex];

            // 3. 암호 진입 메뉴 (1: 시스템설정, 2: 운전설정)
            //    범위 밖이면 안전하게 시스템설정으로
            final pwIdx = (pwMenuVal == 2) ? 1 : 0;
            pwEntryMenu = _labels_pwMenu[pwIdx];

            // 4. 불리언(bool) 값 변환 (1이면 true, 아니면 false)
            stopShowDp     = (stopShVal == 1);
            overDpFan      = (overDpVal == 1);
            multiContact   = (multiCVal == 1);
            blackoutReward = (blackReVal == 1);
            linkContactMisPrevent = (linkCMisPrevVal == 1);

            _loadFailed = false;
          });
          return; // 성공 시 함수 종료
        }
      } catch (e) {
        debugPrint('로드 시도 $attempt 실패: $e');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;
    setState(() {
      _loadFailed = true;
    });
  }

  Future<void> _setRunMode(String newLabel) async {
    final int value;
    switch (newLabel) {
      case '판넬': value = 0; break;
      case '연동': value = 1; break;
      case '원격': value = 2; break;
      default:    value = 3; // 통신(RS485)
    }

    final ok = await widget.writeRegister(34, value);
    if (!mounted) return;

    if (ok) {
      setState(() => runMode = newLabel);
      widget.onRunModeChanged?.call(newLabel);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('동작 모드가 "$newLabel"(으)로 설정되었습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('동작 모드 설정 실패')),
      );
    }
  }

  Future<void> _setBuzzerMode(String newLabel) async {
    final int value;
    switch (newLabel) {
      case '음소거': value = 0; break;
      case 'ON': value = 1; break;
      default:    value = 2; // 자동
    }

    final ok = await widget.writeRegister(72, value);
    if (!mounted) return;

    if (ok) {
      setState(() => buzzerMode = newLabel);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('부저 모드가 "$newLabel"(으)로 설정되었습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('부저 모드 설정 실패')),
      );
    }
  }

  Future<void> _setPwEntryMenu(String newLabel) async {
    final int value = (newLabel == '운전설정') ? 2 : 1;
    final ok = await widget.writeRegister(74, value);
    if (!mounted) return;

    if (ok) {
      setState(() => pwEntryMenu = newLabel);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('암호 진입 메뉴가 "$newLabel"(으)로 설정되었습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('암호 진입 메뉴 설정 실패')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    // 데이터 로딩 중
    if (overDpFan == null ||
        stopShowDp == null ||
        multiContact == null ||
        blackoutReward == null ||
        linkContactMisPrevent == null ||
        buzzerMode == null ||
        pwEntryMenu == null) {
      return const Scaffold(
        backgroundColor: AppColor.bg,
        body: Center(child: CircularProgressIndicator(color: AppColor.duBlue,)),
      );
    }

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('옵션설정'),
            tiles: <SettingsTile>[
              SettingsTile.navigation(
                leading: const Icon(Icons.cable),
                title: const Text('동작 모드'),
                value: Text(runMode != null ? runMode! : ""),
                onPressed: (_) async {
                  final selected = await showRadioPicker<String>(
                    context: context,
                    title: '동작 모드',
                    options: _labels,
                    groupValue: runMode != null ? runMode! : "",
                    labelOf: (s) => s,
                  );
                  if (selected != null && selected != runMode) {
                    await _setRunMode(selected);
                  }
                },
              ),
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 70,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => stopShowDp = nv),
                  errorText: '운전 정지 시 차압 표시 실패',
                ),
                initialValue: stopShowDp!,
                leading: const Icon(Symbols.bar_chart),
                title: Text('운전 정지, 차압 표시'),
                description: Text('가동 정지 상태에서 차압 표시'),
              ),
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 57,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => overDpFan = nv),
                  errorText: '차압 알람 설정 실패',
                ),
                initialValue: overDpFan!,
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('차압 알람, 팬 가동'),
                description: Text('차압 알람시에 팬 계속 가동'),
              ),
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 36,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => multiContact = nv),
                  errorText: '다기능 접점 설정 실패',
                ),
                initialValue: multiContact!,
                leading: const Icon(Symbols.alarm),
                title: Text('다기능 접점 선택'),
                description: Text('수동 솔동작 / MULTI 알람'),
              ),
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 35,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => blackoutReward = nv),
                  errorText: '정전 보상 기능 설정 실패',
                ),
                initialValue: blackoutReward!,
                leading: const Icon(Symbols.refresh),
                title: Text('정전 보상 기능'),
                description: Text('정전 보상 기능 선택'),
              ),
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 71,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => linkContactMisPrevent = nv),
                  errorText: '연동접점 오동작 방지 기능 설정 실패',
                ),
                initialValue: linkContactMisPrevent!,
                leading: const Icon(Symbols.do_not_touch),
                title: Text('연동접점 오동작 방지'),
                description: Text('연동접점 오동작 방지 사용 여부'),
              ),
              SettingsTile.navigation(
                leading: const Icon(Symbols.lock),
                title: const Text('암호 진입 메뉴 설정'),
                description: const Text('암호 진입 메뉴 선택'),
                value: Text(pwEntryMenu!),
                onPressed: (_) async {
                  final selected = await showRadioPicker<String>(
                    context: context,
                    title: '암호 진입 메뉴',
                    options: _labels_pwMenu,
                    groupValue: pwEntryMenu!,
                    labelOf: (s) => s,
                  );
                  if (selected != null && selected != pwEntryMenu) {
                    await _setPwEntryMenu(selected);
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.cable),
                title: const Text('부저 모드'),
                value: Text(buzzerMode != null ? buzzerMode! : ""),
                onPressed: (_) async {
                  final selected = await showRadioPicker<String>(
                    context: context,
                    title: '부저 모드',
                    options: _labels_buzzer,
                    groupValue: buzzerMode != null ? buzzerMode! : "",
                    labelOf: (s) => s,
                  );
                  if (selected != null && selected != buzzerMode) {
                    await _setBuzzerMode(selected);
                  }
                },
              ),
              SettingsTile(
                title: const Text('필터 사용 시간 초기화'),
                trailing: TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text('필터 교체 확인'),
                          content: const Text('필터 사용시간을 초기화하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop(false); // 취소
                              },
                              child: const Text('취소', style: TextStyle(color: Colors.black87),),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop(true); // 확인
                              },
                              child: const Text('확인', style: TextStyle(color: AppColor.duBlue, fontWeight: FontWeight.w700),),
                            ),
                          ],
                        );
                      },
                    );

                    if (confirmed == true) {
                      await widget.writeRegister(11, 1);
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColor.duRed,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('초기화'),
                ),
              ),

            ],
          ),
        ],
      ),
    );
  }
}
