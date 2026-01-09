import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:duclean/services/modbus_manager.dart';

class AlarmSettingPage extends StatefulWidget {
  const AlarmSettingPage({
    super.key,
    required this.writeRegister,
    required this.readRegister,
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
  State<AlarmSettingPage> createState() => _AlarmSettingPageState();
}

class _AlarmSettingPageState extends State<AlarmSettingPage> {
  int? filterReplaceTime; // 필터 교체 시간
  int? filterReplaceRepeatTime; // 필터 교체 재알람 시간
  bool? motorReverse; // 모터 역방향 알람
  int? alarm1Contact; // 알람 1 접점
  int? alarm2Contact; // 알람2 접점

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
      filterReplaceTime = null;
      filterReplaceRepeatTime = null;
      motorReverse = null;
      alarm1Contact = null;
      alarm2Contact = null;
    });

    for (int attempt = 1; attempt <= _maxRetry; attempt++) {
      try {
        // 주소 37번부터 69번까지 포함하도록 33개를 한 번에 읽음
        final List<int>? results = await ModbusManager.instance.readHoldingRange(
          context,
          host: widget.host, // 호스트 정보 필요
          unitId: widget.unitId,
          startAddress: 37,
          count: 33,
          name: 'AlarmSettingsBatch',
        );

        if (results != null && results.length >= 33) {
          if (!mounted) return;
          setState(() {
            // 인덱스 계산: (대상 주소 - 시작 주소)
            filterReplaceTime       = results[0];  // 37 - 37
            alarm1Contact           = results[5];  // 42 - 37
            alarm2Contact           = results[18]; // 55 - 37
            motorReverse            = (results[25] == 1); // 62 - 37
            filterReplaceRepeatTime = results[32]; // 69 - 37
            _loadFailed = false;
          });
          return; // 성공 시 종료
        }
      } catch (e) {
        debugPrint('Attempt $attempt failed: $e');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!mounted) return;
    setState(() {
      _loadFailed = true;
    });
  }



  @override
  Widget build(BuildContext context) {
    if (filterReplaceTime == null || filterReplaceRepeatTime == null || motorReverse == null || alarm1Contact == null
    || alarm2Contact == null) {

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
              margin: const EdgeInsetsDirectional.only(
                top: 4,
                bottom: 100,
              ),

            title: Text("필터"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('필터 교체 시간'),
                value: Text('${filterReplaceTime!} Hour'),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '필터 교체 시간 설정',
                    icon: Icons.timer_outlined,
                    address: 37,
                    initialValue: filterReplaceTime!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 32000,
                    accentColor: AppColor.duBlue,
                    hintText: '0 ~ 32000',
                  );
                  if (saved != null && mounted) {
                    setState(() => filterReplaceTime = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('필터 교체 시간이 저장되었습니다.')),
                    );
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.alarm),
                title: const Text('필터 교체 재알람 시간'),
                value: Text('${filterReplaceRepeatTime} Hour'),
                onPressed: (_) async {
                  final saved = await showRegisterNumberEditor(
                    context: context,
                    title: '필터 교체 재알람 시간 설정',
                    icon: Icons.alarm,
                    address: 37,
                    initialValue: filterReplaceRepeatTime!,
                    writeRegister: widget.writeRegister,
                    min: 0,
                    max: 8760,
                    accentColor: AppColor.duBlue,
                    hintText: '0 ~ 8760',
                  );
                  if (saved != null && mounted) {
                    setState(() => filterReplaceRepeatTime = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('필터 교체 재알람 시간이 저장되었습니다.')),
                    );
                  }
                },
              ),
            ]
          ),
          SettingsSection(
           // title: Text("모터"),
            tiles: [
              SettingsTile.switchTile(
                activeSwitchColor: AppColor.duBlue,

                onToggle: (v) => applyRegisterToggle(
                  context: context,
                  newValue: v,
                  address: 62, // 과차압 팬알람 레지스터
                  writeRegister: widget.writeRegister,
                  setLocalValue: (nv) => setState(() => motorReverse = nv),
                  errorText: '모터 역방향 알람 설정 실패',
                ),

                initialValue: motorReverse!,
                leading: const Icon(Symbols.toys_fan_rounded),
                title: Text('모터 역방향 알람'),
                description: Text('모터 역방향 알람 사용'),
              ),
            ]
          ),
          SettingsSection(
            title: Text("알람"),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Symbols.siren_open),
                title: const Text('알람 1 접점'),
                value: Text(alarm1Contact == 1 ? 'A접점(Normal Open)' : 'B접점(Normal Close)'),
                onPressed: (_) async {
                  final selected = await showRadioPicker<String>(
                    context: context,
                    title: '알람 1 접점',
                    options: const ['A접점(Normal Open)', 'B접점(Normal Close)'],
                    groupValue: (alarm1Contact == 1) ? 'A접점(Normal Open)' : 'B접점(Normal Close)',
                    labelOf: (s) => s,
                  );
                  if (selected == null) return;

                  final v = (selected == 'A접점(Normal Open)') ? 1 : 2;
                  final ok = await widget.writeRegister(42, v);
                  if (!mounted) return;

                  if (ok) {
                    setState(() => alarm1Contact = v);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('알람 1 접점이 저장되었습니다.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('알람 1 접점 저장 실패')),
                    );
                  }
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Symbols.siren_open),
                title: const Text('알람 2 접점'),
                value: Text(alarm2Contact == 1 ? 'A접점(Normal Open)' : 'B접점(Normal Close)'),
                onPressed: (_) async {
                  final selected = await showRadioPicker<String>(
                    context: context,
                    title: '알람 2 접점',
                    options: const ['A접점(Normal Open)', 'B접점(Normal Close)'],
                    groupValue: (alarm2Contact == 1) ? 'A접점(Normal Open)' : 'B접점(Normal Close)',
                    labelOf: (s) => s,
                  );
                  if (selected == null) return;

                  final v = (selected == 'A접점(Normal Open)') ? 1 : 2;
                  final ok = await widget.writeRegister(55, v);
                  if (!mounted) return;

                  if (ok) {
                    setState(() => alarm2Contact = v);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('알람 2 접점이 저장되었습니다.')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('알람 2 접점 저장 실패')),
                    );
                  }
                },
              ),
            ]
          )
        ],
      ),
    );
  }
}
