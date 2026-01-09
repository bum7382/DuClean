import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:duclean/services/modbus_manager.dart';

class PulseSettingPage extends StatefulWidget {
  const PulseSettingPage({
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
        // 주소 26번부터 64번까지(총 39개) 한 번에 읽기
        final List<int>? results = await ModbusManager.instance.readHoldingRange(
          context,
          host: widget.host,
          unitId: widget.unitId,
          startAddress: 26,
          count: 39,           // 64 - 26 + 1
          name: 'PulseSettings',
        );

        if (results != null && results.length >= 39) {
          if (!mounted) return;
          setState(() {
            // 인덱스 계산: 결과 리스트[대상 주소 - 시작 주소(26)]
            final int addCycleVal   = results[0];  // 26 - 26
            final int runDpVal      = results[1];  // 27 - 26
            final int stopDpVal     = results[2];  // 28 - 26
            final int runTimeVal    = results[4];  // 30 - 26
            final int delayTimeVal  = results[5];  // 31 - 26
            final int solCountVal   = results[7];  // 33 - 26
            final int manualCycleVal = results[27]; // 53 - 26
            final int manualModeVal  = results[28]; // 54 - 26
            final int autoTimeVal    = results[38]; // 64 - 26

            // 값 범위 제한(Clamping) 및 할당
            pulseRunDp       = runDpVal.clamp(0, 300);
            pulseStopDp      = stopDpVal.clamp(0, 100);
            pulseRunTime     = runTimeVal.clamp(0, 9900);
            pulseDelayTime   = delayTimeVal.clamp(0, 999);
            pulseSolCount    = solCountVal.clamp(1, 8);
            pulseAutoTime    = autoTimeVal.clamp(0, 3600);
            pulseAddCycle    = addCycleVal.clamp(0, 5);
            pulseManualMode  = (manualModeVal == 1);
            pulseManualCycle = manualCycleVal.clamp(1, 50);

            _loadFailed = false;
          });
          return; // 성공 시 종료
        }
      } catch (e) {
        debugPrint('Pulse 설정 로드 시도 $attempt 실패: $e');
      }

      // 재시도 대기 시간을 300ms로 조정하여 더 빠르게 반응
      await Future.delayed(const Duration(milliseconds: 300));
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
