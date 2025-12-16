import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';

class FrequencySettingPage extends StatefulWidget {
  const FrequencySettingPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;

  @override
  State<FrequencySettingPage> createState() => _AlarmSettingPageState();
}

class _AlarmSettingPageState extends State<FrequencySettingPage> {
  static const List<String> _labels = ['사용안함', '키패드', '전류입력'];
  String? freqMode; // 주파수 출력
  int? freqRun; // 출력 주파수
  int? freqMin; // 최소 주파수
  int? freqMax; // 최대 주파수
  int? freqAdjust; // 주파수 보정

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
      freqMode = null;
      freqRun = null;
      freqMin = null;
      freqMax = null;
      freqAdjust = null;
    });

    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        // null이면 실패로 간주(값을 0으로 대체하지 않음)
        final mode  = await widget.readRegister(50);
        final run = await widget.readRegister(60);
        final min  = await widget.readRegister(52);
        final max = await widget.readRegister(51);
        final adjust = await widget.readRegister(59);

        if (mode != null && run != null && min != null && max != null && adjust != null) {
          if (!mounted) return;
          setState(() {
            final m = (mode ?? 0);
            final safeIndex = (m >= 0 && m < _labels.length) ? m : 0;
            freqMode = _labels[safeIndex];
            freqRun = run  < 0 ? 0 : (run  > 400 ? 400 : run);
            freqMin = min  < 0 ? 0 : (min  > 20 ? 20 : min);
            freqMax = max  < -500 ? -500 : (max  > 500 ? 500 : max);
            freqAdjust = adjust  < 1 ? 1 : (adjust  > 8 ? 8 : adjust);
            _loadFailed = false;
          });
          return;
        }
      } catch (_) {
        // ignore; 다음 attempt로
      }

      // 다음 시도 전 짧은 대기 (지수 백오프 원하면 attempt 사용)
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (!mounted) return;
    setState(() {
      _loadFailed = true;
    });
  }



  @override
  Widget build(BuildContext context) {

    if (freqMode == null || freqRun == null || freqMin == null || freqMax == null || freqAdjust == null) {
      return const Scaffold(
        backgroundColor: AppColor.bg,
        body: Center(child: CircularProgressIndicator(color: AppColor.duBlue,)),
      );
    }

    Future<void> _setFreqMode(String newLabel) async {
      final int value;
      switch (newLabel) {
        case '사용안함': value = 0; break;
        case '키패드': value = 1; break;
        default:    value = 2; // 전류입력
      }
      final ok = await widget.writeRegister(50, value);
      if (!mounted) return;

      if (ok) {
        setState(() => freqMode = newLabel);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주파수 출력 모드가 "$newLabel"(으)로 설정되었습니다.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('추파수 출력 모드 설정 실패')),
        );
      }
    }

    return Scaffold(
      backgroundColor: AppColor.bg,
      body: SettingsList(
        sections: [
          SettingsSection(
            //title: Text("주파수 모드"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.input),
                title: const Text('주파수 선택'),
                value: Text(freqMode != null ? freqMode! : ""),
                onPressed: (_) async {
                  final selected = await showRadioPicker<String>(
                    context: context,
                    title: '주파수 모드',
                    options: _labels,
                    groupValue: freqMode != null ? freqMode! : "",
                    labelOf: (s) => s,
                  );
                  if (selected != null && selected != freqMode) {
                    await _setFreqMode(selected);
                  }
                },
              ),
            ],
          ),
          SettingsSection(
           // title: Text("주파수 설정"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.moving),
                title: const Text('출력 주파수'),
                value: Text('$freqRun Hz'),
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '출력 주파수',
                    icon: Icons.speed,
                    address: 60,
                    initialValue: freqRun!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 400,
                    step: 1,
                    unit: '',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => freqRun = saved);
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.vertical_align_bottom),
                title: const Text('주파수 최소 출력'),
                value: Text('$freqMin Hz'),
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '주파수 최소 출력',
                    icon: Icons.speed,
                    address: 52,
                    initialValue: freqMin!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 20,
                    step: 1,
                    unit: '',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => freqMin = saved);
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.vertical_align_top),
                title: const Text('주파수 최대 출력'),
                value: Text('$freqMax Hz'),
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '주파수 최대 출력',
                    icon: Icons.speed,
                    address: 51,
                    initialValue: freqMax!,
                    writeRegister: widget.writeRegister,
                    min: 30,
                    max: 400,
                    step: 1,
                    unit: '',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => freqMax = saved);
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.display_settings),
                title: const Text('주파수 보정'),
                value: Text('${freqAdjust!} '),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '주파수 보정',
                    icon: Icons.timer_outlined,
                    address: 59,
                    initialValue: freqAdjust!,
                    writeRegister: widget.writeRegister,
                    min: -500,
                    max: 500,
                    accentColor: AppColor.duBlue,
                    hintText: '-500 ~ 500',
                  );
                  if (saved != null && mounted) {
                    setState(() => freqAdjust = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('주파수 보정 값이 저장되었습니다.')),
                    );
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
