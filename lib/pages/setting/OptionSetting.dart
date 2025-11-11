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
  bool? overDpFan;
  String? runMode;

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
      overDpFan = null;
      runMode = null;
    });
    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        final overDp = await widget.readRegister(57);
        final mode = await widget.readRegister(34);
        if (overDp != null && mode != null) {
          if (!mounted) return;
          setState(() {
            overDpFan = (overDp == 1);
            final m = (mode ?? 0);
            final safeIndex = (m >= 0 && m < _labels.length) ? m : 0;
            runMode = _labels[safeIndex];
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
    if (overDpFan == null) {
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
                  address: 57, // 과차압 팬알람 레지스터
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => overDpFan = nv),
                  errorText: '과차압 팬알람 설정 실패',
                ),
                initialValue: overDpFan!,
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('과차압팬작동'),
                description: Text('과차압 알람 발생 시 자동으로 팬을 동작시킵니다.'),
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
