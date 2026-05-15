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
  int? pulseRunTime; // 펄스 동작 시간 (40031, ms)
  int? pulseDelayTime; // 펄스 지연 시간 (40032, s)
  int? pulseSolCount; // 펄싱 솔밸브 개수
  int? pulseAutoTime; // 자동 펄스 시간
  int? pulseAddCycle; // 추가 펄스 주기
  bool? pulseManualMode; // 수동 펄스 모드
  int? pulseManualCycle;  // 수동 펄스 주기
  int? fanRunTimeRaw; // 40057 팬 작동시간 (raw 0~500, 배율 0.1 → ms)
  int? autoPulseStartDelay; // 40074 자동펄스 시작 지연 시간 (0: 사용안함, 1~3600초)

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
      fanRunTimeRaw = null;
      autoPulseStartDelay = null;
    });

    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        // 주소 26번부터 73번까지(총 48개) 한 번에 읽기
        final List<int>? results = await ModbusManager.instance.readHoldingRange(
          context,
          host: widget.host,
          unitId: widget.unitId,
          startAddress: 26,
          count: 48,           // 73 - 26 + 1
          name: 'PulseSettings',
        );

        if (results != null && results.length >= 48) {
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
            final int fanRunTimeVal  = results[30]; // 56 - 26
            final int autoTimeVal    = results[38]; // 64 - 26
            final int autoStartDelayVal = results[47]; // 73 - 26

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
            fanRunTimeRaw    = fanRunTimeVal.clamp(0, 500);
            autoPulseStartDelay = autoStartDelayVal.clamp(0, 3600);

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



  // 0.1 ms 배율 레지스터 편집기. 사용자는 ms(소수 1자리)로 입력하고 raw = round(ms * 10).
  Future<int?> _showScaledMsEditor({
    required BuildContext context,
    required String title,
    required int initialRaw,
    required int minRaw,
    required int maxRaw,
    required Future<bool> Function(int raw) onWriteRaw,
  }) async {
    final double minMs = minRaw * 0.1;
    final double maxMs = maxRaw * 0.1;
    final controller = TextEditingController(
      text: (initialRaw * 0.1).toStringAsFixed(1),
    );
    String? error;

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                Future<void> onSave() async {
                  final parsed = double.tryParse(controller.text.trim());
                  if (parsed == null || parsed < minMs || parsed > maxMs) {
                    setLocal(() => error =
                        '${minMs.toStringAsFixed(1)} ~ ${maxMs.toStringAsFixed(1)} ms 사이의 값을 입력하세요.');
                    return;
                  }
                  final raw = (parsed * 10).round().clamp(minRaw, maxRaw);
                  final ok = await onWriteRaw(raw);
                  if (ok) {
                    Navigator.pop<int>(ctx, raw);
                  } else {
                    setLocal(() => error = '저장 실패');
                  }
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Symbols.toys_fan_rounded, color: AppColor.duBlue),
                        const SizedBox(width: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      cursorColor: AppColor.duBlue,
                      decoration: InputDecoration(
                        hintText:
                            '${minMs.toStringAsFixed(1)} ~ ${maxMs.toStringAsFixed(1)} ms (0.1 단위)',
                        errorText: error,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(color: AppColor.duBlue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(foregroundColor: AppColor.duBlue),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('취소'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: AppColor.duBlue),
                          onPressed: onSave,
                          child: const Text('저장'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (pulseRunDp == null || pulseStopDp == null || pulseRunTime == null || pulseDelayTime == null || pulseSolCount  == null ||
        pulseAutoTime  == null || pulseAddCycle  == null || pulseManualMode == null || pulseManualCycle  == null ||
        fanRunTimeRaw == null || autoPulseStartDelay == null) {
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
                    address: 28,
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
                value: Text('${pulseDelayTime!} 초'),
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
                    hintText: '0 ~ 999 (초)',
                  );
                  if (saved != null && mounted) {
                    setState(() => pulseDelayTime = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('펄스 지연 시간이 저장되었습니다.')),
                    );
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Symbols.toys_fan_rounded),
                title: const Text('팬 작동시간'),
                value: Text('${(fanRunTimeRaw! * 0.1).toStringAsFixed(1)} ms'),
                onPressed: (_) async {
                  final saved = await _showScaledMsEditor(
                    context: context,
                    title: '팬 작동시간',
                    initialRaw: fanRunTimeRaw!,
                    minRaw: 0,
                    maxRaw: 500,
                    onWriteRaw: (raw) => widget.writeRegister(56, raw),
                  );
                  if (saved != null && mounted) {
                    setState(() => fanRunTimeRaw = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('팬 작동시간이 저장되었습니다.')),
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
                leading: const Icon(Icons.timer_outlined),
                title: const Text('자동펄스 시작 지연 시간'),
                description: const Text('운전 시작 후 자동펄스 개시까지 지연(0: 사용안함)'),
                value: Text(autoPulseStartDelay! == 0
                    ? '사용안함'
                    : '${autoPulseStartDelay!} 초'),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '자동펄스 시작 지연 시간',
                    icon: Icons.timer_outlined,
                    address: 73,
                    initialValue: autoPulseStartDelay!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 3600,
                    accentColor: AppColor.duBlue,
                    hintText: '0(사용안함) ~ 3600',
                  );
                  if (saved != null && mounted) {
                    setState(() => autoPulseStartDelay = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('자동펄스 시작 지연 시간이 저장되었습니다.')),
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
