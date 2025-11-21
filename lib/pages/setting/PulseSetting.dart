import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';

class PulseSettingPage extends StatefulWidget {
  const PulseSettingPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;

  @override
  State<PulseSettingPage> createState() => _AlarmSettingPageState();
}

class _AlarmSettingPageState extends State<PulseSettingPage> {
  int? pulseRunDp; // 펄스 작동 차압
  int? pulseStopDp; // 펄스 정지 편차
  int? pulseRunTime; // 펄스 동작 시간
  int? pulseDelayTime; // 펄스 지연 시간
  int? pulseSolCount; // 펄싱 솔밸브 개수
  int? pulseAutoTime; // 자동 펄스 시간
  int? pulseAddCycle; // 추가 펄스 주기
  bool? pulseManualMode; // 수동 펄스 모드
  int? pulseManualCycle;  // 수동 펄스 주기

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
      pulseRunDp = null;
      pulseStopDp = null;
      pulseRunTime = null;
      pulseDelayTime = null;
      pulseSolCount = null;
      pulseAutoTime = null;
      pulseAddCycle = null;
      pulseManualMode = null;
      pulseManualCycle = null;
    });

    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        // null이면 실패로 간주(값을 0으로 대체하지 않음)
        final runDp  = await widget.readRegister(27);
        final stopDp = await widget.readRegister(28);
        final runTime  = await widget.readRegister(30);
        final delayTime = await widget.readRegister(31);
        final solCount = await widget.readRegister(33);
        final autoTime = await widget.readRegister(64);
        final addCycle = await widget.readRegister(26);
        final manualMode = await widget.readRegister(54);
        final manualCycle = await widget.readRegister(53);

        if (runDp != null && stopDp != null && runTime != null && delayTime != null && solCount != null &&
            autoTime != null && addCycle != null && manualMode != null && manualCycle != null) {
          if (!mounted) return;
          setState(() {
            pulseRunDp = runDp  < 0 ? 0 : (runDp  > 300 ? 300 : runDp);
            pulseStopDp = stopDp  < 0 ? 0 : (stopDp  > 100 ? 100 : stopDp);
            pulseRunTime = runTime  < 0 ? 0 : (runTime  > 9900 ? 9900 : runTime);
            pulseDelayTime = delayTime  < 0 ? 0 : (delayTime  > 999 ? 999 : delayTime);
            pulseSolCount = solCount  < 1 ? 1 : (solCount  > 8 ? 8 : solCount);
            pulseAutoTime = autoTime  < 0 ? 0 : (autoTime  > 3600 ? 3600 : autoTime);
            pulseAddCycle = addCycle  < 0 ? 0 : (addCycle  > 5 ? 5 : addCycle);
            pulseManualMode = (manualMode == 1);
            pulseManualCycle = manualCycle  < 1 ? 1 : (manualCycle  > 50 ? 50 : manualCycle);
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
    if (pulseRunDp == null || pulseStopDp == null || pulseRunTime == null || pulseDelayTime == null || pulseSolCount  == null ||
        pulseAutoTime  == null || pulseAddCycle  == null || pulseManualMode == null || pulseManualCycle  == null) {
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
            //title: Text("펄스 설정"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.speed),
                title: const Text('펄스 작동 차압'),
                value: Text('$pulseRunDp mmAq'), // 화면에 보여줄 현재값(보유 중인 state 사용)
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '펄스 작동 차압',
                    icon: Icons.speed,
                    address: 27,                 // #60 레지스터
                    initialValue: pulseRunDp!,       // 현재값
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 300,
                    step: 1,
                    //unit: ' mmAq',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseRunDp = saved);  // 로컬 UI 반영
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.stop_circle),
                title: const Text('펄스 정지 편차'),
                value: Text('$pulseStopDp mmAq'), // 화면에 보여줄 현재값(보유 중인 state 사용)
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '펄스 정지 편차',
                    icon: Icons.speed,
                    address: 27,                 // #60 레지스터
                    initialValue: pulseStopDp!,       // 현재값
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 100,
                    step: 1,
                    //unit: ' mmAq',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseStopDp = saved);  // 로컬 UI 반영
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('펄스 동작 시간'),
                value: Text('${pulseRunTime!} ms'),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '펄스 동작 시간',
                    icon: Icons.timer_outlined,
                    address: 30,
                    initialValue: pulseRunTime!,
                    writeRegister: widget.writeRegister,
                    min: 10,
                    max: 9990,
                    accentColor: AppColor.duBlue,
                    hintText: '10 ~ 9990',
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseRunTime = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('펄스 동작 시간이 저장되었습니다.')),
                    );
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.pause_circle),
                title: const Text('펄스 지연 시간'),
                value: Text('${pulseDelayTime!} ms'),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '펄스 지연 시간',
                    icon: Icons.timer_outlined,
                    address: 31,
                    initialValue: pulseDelayTime!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 999,
                    accentColor: AppColor.duBlue,
                    hintText: '0 ~ 999',
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseDelayTime = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('펄스 지연 시간이 저장되었습니다.')),
                    );
                  }
                },
              ),
            ],
          ),
          SettingsSection(
            //title: Text("솔밸브"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.format_list_numbered),
                title: const Text('펄싱 솔밸브 개수'),
                value: Text('$pulseSolCount 개'), // 화면에 보여줄 현재값(보유 중인 state 사용)
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '펄싱 솔밸브 개수',
                    icon: Icons.speed,
                    address: 33,
                    initialValue: pulseSolCount!,       // 현재값
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 8,
                    step: 1,
                    unit: ' 개',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseSolCount = saved);  // 로컬 UI 반영
                  }
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text("자동/수동 펄스 설정"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.auto_mode),
                title: const Text('자동 펄스 시간'),
                value: Text('${pulseAutoTime!} 초'),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '자동 펄스 시간',
                    icon: Icons.auto_mode,
                    address: 64,
                    initialValue: pulseAutoTime!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 3600,
                    accentColor: AppColor.duBlue,
                    hintText: '0 ~ 3600',
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseAutoTime = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('자동 펄스 시간이 저장되었습니다.')),
                    );
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.start),
                title: const Text('추가 펄스 주기'),
                value: Text('$pulseAddCycle 회'), // 화면에 보여줄 현재값(보유 중인 state 사용)
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '추가 펄스 주기',
                    icon: Icons.speed,
                    address: 26,
                    initialValue: pulseAddCycle!,       // 현재값
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 5,
                    step: 1,
                    unit: ' 회',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseAddCycle = saved);  // 로컬 UI 반영
                  }
                },
              ),
            ],
          ),
          SettingsSection(
            //title: Text("수동 펄스"),
            tiles: [
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,
                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 54,
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => pulseManualMode = nv),
                  errorText: '수동 펄스 모드 설정 실패',
                ),
                initialValue: pulseManualMode!,
                leading: const Icon(Symbols.swipe),
                title: Text('수동 펄스 모드'),
                description: Text('수동 / 전자동'),
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.repeat),
                title: const Text('수동 펄스 주기'),
                value: Text('$pulseManualCycle 회'), // 화면에 보여줄 현재값(보유 중인 state 사용)
                onPressed: (_) async {
                  final saved = await showDialRegisterEditor(
                    context: context,
                    title: '수동 펄스 주기',
                    icon: Icons.speed,
                    address: 53,
                    initialValue: pulseManualCycle!,       // 현재값
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 50,
                    step: 1,
                    unit: ' 회',
                    accentColor: AppColor.duBlue,
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseManualCycle = saved);  // 로컬 UI 반영
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
