import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:duclean/services/modbus_manager.dart';

class FrequencySettingPage extends StatefulWidget {
  const FrequencySettingPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
    required this.host,
    required this.unitId,
    required this.name,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;
  final String host;
  final int unitId;
  final String name;

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
        // 50번부터 60번까지 총 11개의 레지스터를 한 번에 읽기
        final List<int>? results = await ModbusManager.instance.readHoldingRange(
          context,
          host: widget.host,
          unitId: widget.unitId,
          startAddress: 50,
          count: 11,
          name: 'FrequencySettings',
        );

        if (results != null && results.length >= 11) {
          if (!mounted) return;
          setState(() {
            // 인덱스 계산: 결과 리스트[대상 주소 - 시작 주소]
            final int modeVal   = results[0];  // 주소 50
            final int maxVal    = results[1];  // 주소 51
            final int minVal    = results[2];  // 주소 52
            final int adjVal    = results[9];  // 주소 59 (59 - 50 = 9)
            final int runVal    = results[10]; // 주소 60 (60 - 50 = 10)

            // 1. Mode 설정
            final safeIndex = (modeVal >= 0 && modeVal < _labels.length) ? modeVal : 0;
            freqMode = _labels[safeIndex];

            // 2. 값 범위 제한(Clamping) 및 할당
            freqRun    = runVal.clamp(0, 400);
            freqMin    = minVal.clamp(0, 20);
            freqMax    = maxVal.clamp(-500, 500); // 주의: ModbusManager가 signed를 지원해야 함
            freqAdjust = adjVal.clamp(1, 8);

            _loadFailed = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('로드 시도 $attempt 실패: $e');
      }

      // 다음 시도 전 대기 시간 단축 (속도 향상)
      await Future.delayed(const Duration(milliseconds: 300));
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
