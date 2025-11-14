import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';


class OptionSettingPage extends StatefulWidget {
  const OptionSettingPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
    this.onRunModeChanged,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;
  final void Function(String)? onRunModeChanged;

  @override
  State<OptionSettingPage> createState() => _OptionSettingPageState();
}

class _OptionSettingPageState extends State<OptionSettingPage> {
  static const List<String> _labels = ['판넬', '연동', '원격', '통신(RS485)'];
  String? runMode;  // 운전 모드
  bool? stopShowDp;  // 운전 정지 시 차압 표시
  bool? overDpFan;  // 과차압 팬작동
  bool? multiContact; // 다기능 접점
  bool? blackoutReward; // 정전 보상

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
    });
    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        final mode = await widget.readRegister(34);
        final stopShow = await widget.readRegister(70);
        final overDp = await widget.readRegister(57);
        final multiC = await widget.readRegister(36);
        final blackRe = await widget.readRegister(35);
        if (overDp != null && mode != null && stopShow != null && multiC != null && blackRe != null) {
          if (!mounted) return;
          setState(() {
            final m = (mode ?? 0);
            final safeIndex = (m >= 0 && m < _labels.length) ? m : 0;
            runMode = _labels[safeIndex];
            stopShowDp = (stopShow == 1);
            overDpFan = (overDp == 1);
            multiContact = (multiC == 1);
            blackoutReward = (blackRe == 1);
            _loadFailed = false;
          });
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
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


  @override
  Widget build(BuildContext context) {
    // 데이터 로딩 중
    if (overDpFan == null || stopShowDp == null || stopShowDp == null || multiContact == null || blackoutReward == null) {
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
            tiles: <SettingsTile>[
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
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('운전 정지 시 차압 표시'),
                description: Text('운전 정지 시 차압을 표시합니다.'),
              ),
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 57,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => overDpFan = nv),
                  errorText: '과차압 팬알람 설정 실패',
                ),
                initialValue: overDpFan!,
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('과차압팬작동'),
                description: Text('과차압 알람 발생 시 자동으로 팬을 동작시킵니다.'),
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
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('다기능 접점'),
                description: Text('다기능 접점을 설정합니다. (수동 솔동작 / MULTI 알람)'),
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
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('정전보상'),
                description: Text('정전 보상 기능 사용 여부를 설정합니다.'),
              ),
              SettingsTile(
                title: const Text('필터 사용시간 초기화'),
                trailing: TextButton(
                  onPressed: () async {
                    await widget.writeRegister(11, 1);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('초기화'),
                ),
              ),

              SettingsTile.navigation(
                leading: const Icon(Icons.tune),
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
            ],
          ),
        ],
      ),
    );
  }
}
