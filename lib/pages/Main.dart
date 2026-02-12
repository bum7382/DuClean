// dart 기본 라이브러리
import 'dart:async';
import 'package:flutter/material.dart';

// 페이지
import 'package:duclean/pages/schedule/Schedule.dart';
import 'package:duclean/pages/setting/AlarmSetting.dart';
import 'package:duclean/pages/setting/FrequencySetting.dart';
import 'package:duclean/pages/setting/OptionSetting.dart';
import 'package:duclean/pages/setting/PulseSetting.dart';
import 'package:duclean/pages/detail/DpDetail.dart';
import 'package:duclean/pages/detail/PowerDetail.dart';

// 기타 도구
import 'package:duclean/res/auth_guard.dart'; // 권한 설정 페이지
import 'package:duclean/services/routes.dart';  // 라우트
import 'package:duclean/services/auth_service.dart';  // 권한 설정 서비스
import 'package:duclean/services/alarm_store.dart'; // 알람 저장

// 모드버스
import 'package:modbus_client/modbus_client.dart';  // 모드버스 패키지
import 'package:modbus_client_tcp/modbus_client_tcp.dart';  // 모드버스 패키지
import 'package:duclean/services/modbus_manager.dart';  // 모드버스 설정

// provider
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/providers/dp_history.dart';
import 'package:duclean/providers/power_history.dart';

// 디자인
import 'package:material_symbols_icons/symbols.dart'; // 심볼
import 'package:animations/animations.dart';  // 화면 전환 애니메이션
import 'package:duclean/common/context_extensions.dart';  // 화면 크기
import 'package:duclean/res/Constants.dart';  // 상수
import 'package:duclean/res/customWidget.dart'; // 커스텀 위젯


class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // 통신 설정
  String _host = "";
  String _mac = "";
  int _unitId = 0;
  String _deviceName = "";
  bool _bootStrapped = false;

  // 폴링 상태
  ModbusClientTcp? _client;
  Timer? _poller;

  // 폴링 재진입 방지
  bool _pollingBusy = false;
  static const Duration _pollInterval = Duration(milliseconds: 1000);

  // 전체(모든 기기) 미해제 알람 배지
  int _globalAlarmOpenCount = 0;
  Timer? _alarmBadgeTimer;

  // 읽기 그룹: 0~69 입력레지스터(FC04) 읽기
  late final ModbusElementsGroup _inputs;

  // UI 표시값
  var diffPressure = 0; // 차압
  var power1 = 0.0; // 전류 1
  var power2 = 0.0; // 전류 2

  // 운전시간
  int operationTime = 0;

  String pulseStatus = "펄스 정지"; // 펄스 운전상태
  Color pulseColor = Color(0xffF71041);
  bool motorStatus = false; // 송풍기 운전상태

  bool solValveStatus = false; // 솔밸브 동작상태 - 필터 펄싱때만 표시하도록 하는 변수

  // 필터 정보 활성화 25.10.31
  var filterTime = 0; // 필터 교체 시간
  var filterCount = 0; // 필터 교체 횟수

  int activeSolValveNo = 0; // 동작 솔밸브 번호
  var manualPulseStatus; // 수동펄스상태

  var ao1diffPressure; // AO1 차압출력
  var ao2Frequency; // AO2 주파수 출력

  var alarm1Output; // 알람 1 출력
  var alarm2Output; // 알람 2 출력
  var alarmBuzzerFlag; // 알람부저플래그
  var alarmCode; // 알람발생코드

  var preAlarm = -1; // 이전 알람
  var isAlarmClear = true; // 알람 해제 여부
  var currentAlarm = 0; // 현재 알람
  bool isAlarmChanged = false; // 알람 변경 여부
  var alarmDate; // 알람 발생 시각

  var alarmCount = 0; // 발생알람개수
  var diStatusValue; // DI 상태값
  var firmwareVersion = 0.0; // 펌웨어 버전- 표시 추가 26.02.12

  // Holding Register(4x)
  final runModeList = ['판넬', '연동', '원격', '통신(RS485)']; // 동작 설정
  var runMode = "";

  var fanFreq = 0; // #60 송풍기 가동 주파수
  var pulseDiff = 0; // #27 펄스 작동 차압
  var solCount = 0; // #30 동작 솔 밸브 갯수

  var dpHighLimit = 0; // 과차압 설정
  var dpHighAlarmDelay = 0; // 과차압 알람지연
  var dpLowLimit = 0; // 저차압 설정
  var dpLowAlarmDelay = 0; // 저차압 알람지연
  var powerLimit = 0; // 과전류 설정
  var powerDiff = 0; // 전류 편차

  int freqSelectMode = 0; // 주파수 출력
  int pulseAutoMode = 0;  // 수동 펄스모드

  bool pulseDescription = false;  // 펄싱 차압 <-> 솔 밸브
  bool _loading = true;
  int _pollFailCount = 0;
  static const int _failToShowLoading = 2;

  @override
  void initState() {
    super.initState();
    _inputs = ModbusElementsGroup(
      List.generate(
        70,
        (i) => ModbusUint16Register(
          name: 'in_$i',
          type: ModbusElementType.inputRegister,
          address: i,
        ),
      ),
    );
  }

  int _currentIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootStrapped) return;

    final sel = context.read<SelectedDevice>().current;
    if (sel == null) {
      // 선택 장치가 없으면 뒤로
      Future.microtask(() => Navigator.of(context).pop());
      return;
    }

    _host = sel.address;
    _mac = sel.macAddress;
    _unitId = sel.unitId;
    _deviceName = sel.name;
    _bootStrapped = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 초기 읽기 먼저
      await _startPolling();
      await _readOnEnter();
      // 그 다음 폴링 시작
    });

    ModbusManager.instance.startAlarmWatch(
      host: _host,
      unitId: _unitId,
      name: _deviceName,
    );
    _alarmBadgeTimer?.cancel();
    _alarmBadgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickGlobalAlarmCount();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    _poller = null;
    _alarmBadgeTimer?.cancel();
    _alarmBadgeTimer = null;
    // 연결 해제
    // ModbusManager.instance.disconnect(context, host: _host, unitId: _unitId);
    super.dispose();
  }

  // 첫 진입 시 R/W 레지스터 값 읽어서 초기화
  Future<void> _readOnEnter() async {
    final list = await ModbusManager.instance.readHoldingRange(
      context,
      host: _host,
      unitId: _unitId,
      startAddress: 26,
      count: 45,
      // 26~70
      name: _deviceName,
    );

    if (!mounted) return;
    if (list == null || list.isEmpty) {
      setState(() => _loading = false);
      Navigator.of(context).pop(); // 목록으로 튕기기
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기기 응답이 없습니다. 네트워크 상태를 확인하세요.')),
      );
      return;
    }

    int _get(int addr, {int defaultValue = 0}) {
      final idx = addr - 26;
      if (idx < 0 || idx >= list.length) return defaultValue;
      return list[idx];
    }

    final diff = _get(27, defaultValue: 0);
    final sol = _get(33, defaultValue: 0);
    final mode = _get(34, defaultValue: 0);
    final freq = _get(60, defaultValue: 0);

    final dHLimit = _get(29, defaultValue: 0);
    final dHAlarmD = _get(65, defaultValue: 0);
    final dLLimit = _get(67, defaultValue: 0);
    final dLAlarmD = _get(68, defaultValue: 0);
    final pLimit = _get(32, defaultValue: 0);
    final pDiff = _get(44, defaultValue: 0);

    final fMode = _get(50, defaultValue: 0);
    final pAuto = _get(54, defaultValue: 0);

    if (!mounted) return;
    setState(() {
      runMode = (mode != null && mode >= 0 && mode < runModeList.length)
          ? runModeList[mode]
          : '';

      fanFreq = freq;
      pulseDiff = diff;
      solCount = sol;
      dpHighLimit = dHLimit;
      dpHighAlarmDelay = dHAlarmD;
      dpLowLimit = dLLimit;
      dpLowAlarmDelay = dLAlarmD;
      powerLimit = pLimit;
      powerDiff = pDiff;
      freqSelectMode = fMode;
      pulseAutoMode = pAuto;
    });
  }

  Future<void> _tickGlobalAlarmCount() async {
    // AlarmStore는 최신순으로 반환됨
    final all = await AlarmStore.loadAllSortedDesc();

    // 기기별 최신 레코드만 본다(이전 미해제 레코드가 남아있어도 중복 집계 방지)
    final seen = <String, bool>{};
    var open = 0;
    for (final e in all) {
      final key = '${e.host}#${e.unitId}';
      if (seen.containsKey(key)) continue; // 이미 최신 레코드 반영됨
      seen[key] = true;
      if (e.clearedTsMs == null) open++; // 최신이 미해제면 그 기기는 "알람 진행 중"
    }

    if (!mounted) return;
    setState(() => _globalAlarmOpenCount = open);
  }

  // Read Input Register 함수
  Future<void> _startPolling() async {
    _client ??= await ModbusManager.instance.ensureConnected(
      context,
      host: _host,
      unitId: _unitId,
      name: _deviceName,
    );

    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) async {
      if (!mounted) return;
      if (_pollingBusy) return;
      _pollingBusy = true;
      try {
        if (_client == null || !(_client!.isConnected)) {
          _client = await ModbusManager.instance.ensureConnected(
            context,
            host: _host,
            unitId: _unitId,
            name: _deviceName,
          );
        }

        await _client!.send(_inputs.getReadRequest());

        final dp = (_inputs[0] as ModbusUint16Register).value?.toInt() ?? 0;
        final p1 =
            ((_inputs[1] as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        final p2 =
            ((_inputs[2] as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        final opHi = (_inputs[11] as ModbusUint16Register).value?.toInt() ?? 0;
        final opLo = (_inputs[12] as ModbusUint16Register).value?.toInt() ?? 0;
        final pul = (_inputs[13] as ModbusUint16Register).value?.toInt() ?? 0;
        final run = (_inputs[14] as ModbusUint16Register).value?.toInt() ?? 0;
        final solNumber =
            (_inputs[18] as ModbusUint16Register).value?.toInt() ??
                0; //동작 솔밸브 번호

        final curAlarm =
            (_inputs[25] as ModbusUint16Register).value?.toInt() ?? 0;
        final alarmCnt =
            (_inputs[40] as ModbusUint16Register).value?.toInt() ?? 0;

        final filterUsed =
            (_inputs[16] as ModbusUint16Register).value?.toInt() ?? 0;
        final filterChange =
            (_inputs[17] as ModbusUint16Register).value?.toInt() ?? 0;
        // 펌웨어 버전 값 호출 추가 : 26.02.12
        final fwVer =
            ((_inputs[69] as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        context.read<ConnectionRegistry>().setAlarmCode(
          _host,
          _unitId,
          curAlarm,
        );

        // 차압 히스토리
        context.read<DpHistory>().addPointFor(_host, _unitId, dp.toDouble());

        // 전류 히스토리 (power1 = 채널 1, power2 = 채널 2)
        context.read<PowerHistory>().addPointFor(_host, _unitId, 1, p1);
        context.read<PowerHistory>().addPointFor(_host, _unitId, 2, p2);

        if (!mounted) return;
        setState(() {
          firmwareVersion = fwVer;//기판 펌웨어 버전 표시 추가: 26.02.12
          diffPressure = dp;
          power1 = p1;
          power2 = p2;
          operationTime = ((opHi & 0xFFFF) << 16) | (opLo & 0xFFFF);
          pulseStatus = pulseStatusLabel(pul);
          motorStatus = (run != 0);
          currentAlarm = curAlarm;
          alarmCount = alarmCnt;
          filterTime = filterUsed;
          filterCount = filterChange;
          _pollFailCount = 0;
          activeSolValveNo = solNumber;
                    _loading = false;
        });
      } catch (e) {
        if (!mounted) return;

        setState(() {
          _pollFailCount++;

          // 2회 연속 실패 시 '연결 확인 중' 커버 표시
          if (_pollFailCount >= _failToShowLoading) {
            _loading = true;
          }
        });

        debugPrint('폴링 실패 카운트: $_pollFailCount, 에러: $e');

        // 연속 10회(약 10초) 실패 시 자동 퇴장
        if (_pollFailCount >= 10) {
          _poller?.cancel(); // 폴링 중지
          _poller = null;

          // 이전 화면(ConnectList)으로 돌아가기
          Navigator.of(context).popUntil((route) => route.settings.name == Routes.connectListPage);

          // 사용자에게 알림 표시
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_deviceName 장치와의 통신이 원활하지 않아 목록으로 돌아갑니다.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          return; // 더 이상 진행하지 않음
        }

        try {
          await _client?.disconnect();
        } catch (_) {}
        _client = null;
      } finally {
        _pollingBusy = false;
      }
    });
  }

  Future<bool> writeRegister(int address, int value) {
    return ModbusManager.instance.writeHolding(
      context,
      host: _host,
      unitId: _unitId,
      name: _deviceName,
      address: address,
      value: value,
    );
  }

  Future<int?> readRegister(int address) {
    return ModbusManager.instance.readHolding(
      context,
      host: _host,
      unitId: _unitId,
      name: _deviceName,
      address: address,
    );
  }

  // 펄스 모드 라벨화
  String pulseStatusLabel(int code) {
    switch (code) {
      case 0:
        pulseColor = Color(0xffF71041);
        return "펄스 정지";
      case 1:
        pulseColor = Color(0xff4BFC06);
        return "자동 펄스";
      case 2:
        pulseColor = Color(0xffF4FD00);
        return pulseAutoMode == 0 ? "수동 펄스" : "전자동 펄스";
      case 3:
        pulseColor = Color(0xff4BFC06);
        return "추가 펄스";
      case 4:
        pulseColor = Color(0xff4BFC06);
        return "일시 정지";
      default:
        pulseColor = Color(0xffF71041);
        return "알수없음($code)";
    }
  }

  // 모터 실행 토글 함수
  Future<void> _toggleRun() async {
    try {
      if (motorStatus) {
        await writeRegister(0, 0); // 정지
      } else {
        await writeRegister(0, 1); // 운전
      }
      if (!mounted) return;
      setState(() {
        motorStatus = !motorStatus;
      });
    } catch (e) {
      debugPrint('토글 실패: $e');
    }
  }

  // 부저 함수
  void _togglePulse() {
    setState(() {
      pulseDescription = !pulseDescription; // 현재 상태를 반전시킵니다.
    });
  }

  // 펄스 정보
  Future<void> _toggleBuzzer() async {
    try {
      if (!mounted) return;
      await writeRegister(1, 1);
    } catch (e) {
      debugPrint('쓰기 실패: $e');
    }
  }

  Widget _buildCurrentTab(BuildContext context) {
    final pages = <Widget>[
      ColoredBox(
        color: AppColor.bg,
        child: _HomeTab(
          w: context.screenWidth,
          h: context.screenHeight,
          portrait: context.isPortrait,
          deviceName: _deviceName,//Body TOP
          hostIP:_host,//Body 2row
          stationID:_unitId,//Body 2row sub
          fwVer:firmwareVersion,//기판 펌웨어 버전 표시 추가: 26.02.12
          diffPressure: diffPressure,
          power1: power1,
          power2: power2,
          operationTime: operationTime,
          runMode: runMode,
          fanFreq: fanFreq,
          pulseDiff: pulseDiff,
          solCount: solCount,
          motorStatus: motorStatus,
          pulseStatus: pulseStatus,
          pulseColor: pulseColor,
          alarmCount: alarmCount,
          filterTime: filterTime,
          filterCount: filterCount,
          activeSolValveNo: activeSolValveNo,
          dpHighLimit: dpHighLimit,
          dpHighAlarmDelay: dpHighAlarmDelay,
          dpLowLimit: dpLowLimit,
          dpLowAlarmDelay: dpLowAlarmDelay,
          powerLimit: powerLimit,
          powerDiff: powerDiff,
          pulseDescription: pulseDescription,
          freqSelectMode: freqSelectMode,
          readRegister: readRegister,
          writeRegister: writeRegister,
          onToggleRun: _toggleRun,
          onToggleBuzzer: _toggleBuzzer,
          onTogglePulse: _togglePulse,
        ),
      ),
      AuthGuard(
        isTab: true,
        child: FrequencySettingPage(
          readRegister: (addr) => readRegister(addr),
          writeRegister: (addr, val) => writeRegister(addr, val),
          host: _host,
          unitId: _unitId,
          name: _deviceName,
        ),
      ),
      AuthGuard(
        isTab: true,
        child: PulseSettingPage(
          readRegister: (addr) => readRegister(addr),
          writeRegister: (addr, val) => writeRegister(addr, val),
          host: _host,
          unitId: _unitId,
          name: _deviceName,
        ),
      ),
      AuthGuard(
        isTab: true,
        child: AlarmSettingPage(
          readRegister: (addr) => readRegister(addr),
          writeRegister: (addr, val) => writeRegister(addr, val),
          host: _host,
          unitId: _unitId,
          name: _deviceName,
        ),
      ),
      AuthGuard(
        isTab: true,
        child: OptionSettingPage(
          readRegister: (addr) => readRegister(addr),
          writeRegister: (addr, val) => writeRegister(addr, val),
          host: _host,
          unitId: _unitId,
          name: _deviceName,
          onRunModeChanged: (label) {
            if (!mounted) return;
            setState(() {
              runMode = label;
            });
          },
        ),
      ),
    ];

    return pages[_currentIndex];
  }

  @override
  Widget build(BuildContext context) {
    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    // 세로 모드 여부
    final portrait = context.isPortrait;

    final alarmAt = context.select<ConnectionRegistry, DateTime?>(
      (r) => r.stateOf(_host, _unitId).alarmAt,
    );

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.duBlue,
        centerTitle: true,
        title: const SizedBox.shrink(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // 이전에 열려있던 페이지 모두 정리 후 connectListPage로 이동
            Navigator.of(context).pushNamedAndRemoveUntil(
              Routes.connectListPage,
                  (route) => false, // 이전의 모든 기록을 지움
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: Row(
              children: [
                // 알람
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      Routes.alarmPage,
                      arguments: <String, dynamic>{
                        'host': _host,
                        'mac': _mac,
                        'name': _deviceName,
                        'date': alarmAt,
                      },
                    );
                  },
                  icon: SizedBox(
                    width: 30,
                    height: 30,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 알람
                        Align(
                          alignment: Alignment.center,
                          child: Icon(
                            alarmCount > 0
                                ? Icons.notifications_on_outlined
                                : Icons.notifications_none,
                            size: 30,
                            color: alarmCount > 0
                                ? Colors.red
                                : Colors.white,
                            weight: 100,
                          ),
                        ),
                        if (alarmCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              constraints: const BoxConstraints(minWidth: 18),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                alarmCount.toString(),// 알람 개수 변수 수정- 25.12.11
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 스케줄
                IconButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        transitionDuration: const Duration(milliseconds: 300),
                        reverseTransitionDuration: const Duration(milliseconds: 300),
                        pageBuilder: (context, animation, secondaryAnimation) {
                          return AuthGuard(
                            child: SchedulePage(
                              readRegister: (addr) => readRegister(addr),
                              writeRegister: (addr, val) => writeRegister(addr, val),
                            ),
                          );
                        },
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_month, color: Colors.white, size: 30),
                ),
              ],
            ),
          ),
        ],
        flexibleSpace: SafeArea(
          child: Stack(
            //alignment: Alignment.topLeft,
            children: [
              Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/logo_white.png', width: 95),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        AppConst.version,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColor.duBlue,
        currentIndex: _currentIndex,
        onTap: (i) async {
          if (i == _currentIndex) return;
          setState(() => _currentIndex = i);
          // 홈 탭으로 돌아올 때 최신값 재읽기
          if (i == 0) {
            await _readOnEnter();
          }
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: '주파수 설정'),
          BottomNavigationBarItem(icon: Icon(Symbols.valve), label: '펄스 설정'),
          BottomNavigationBarItem(
            icon: Icon(Symbols.notification_settings),
            label: '알람 설정',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handyman_outlined),
            label: '옵션 설정',
          ),
        ],
      ),
      body: Stack(
        children: [
          PageTransitionSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder:
                (
                  Widget child,
                  Animation<double> animation,
                  Animation<double> secondaryAnimation,
                ) {
                  return SharedAxisTransition(
                    animation: animation,
                    secondaryAnimation: secondaryAnimation,
                    transitionType: SharedAxisTransitionType.horizontal,
                    child: child,
                  );
                },
            child: KeyedSubtree(
              key: ValueKey<int>(_currentIndex),
              child: _buildCurrentTab(context),
            ),
          ),

          if (_loading && _currentIndex == 0) const _LoadingCover(),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.w,
    required this.h,
    required this.portrait,
    required this.deviceName,
    required this.hostIP,
    required this.stationID,
    required this.diffPressure,
    required this.power1,
    required this.power2,
    required this.operationTime,
    required this.runMode,
    required this.fanFreq,
    required this.pulseDiff,
    required this.solCount,
    required this.motorStatus,
    required this.pulseStatus,
    required this.pulseColor,
    required this.alarmCount,
    required this.filterTime,
    required this.filterCount,
    required this.activeSolValveNo,
    required this.onToggleRun,
    required this.onToggleBuzzer,
    required this.onTogglePulse,
    required this.pulseDescription,
    required this.dpHighLimit,
    required this.dpHighAlarmDelay,
    required this.dpLowLimit,
    required this.dpLowAlarmDelay,
    required this.powerLimit,
    required this.powerDiff,
    required this.readRegister,
    required this.writeRegister,
    required this.freqSelectMode,
    required this.fwVer,
    //firmwareVersion = fwVer;기판 펌웨어 버전 표시 추가: 26.02.12
  });
  final double fwVer; // 펌웨어 버전
  final double w, h;
  final bool portrait;
  final String deviceName;
  final String hostIP;
  final int stationID;
  final int diffPressure,
      operationTime,
      fanFreq,
      pulseDiff,
      solCount,
      alarmCount;
  final int dpHighLimit,
      dpHighAlarmDelay,
      dpLowLimit,
      dpLowAlarmDelay,
      powerLimit,
      freqSelectMode,
      powerDiff;

  final int filterTime;
  final int filterCount;
  final double power1, power2;
  final String runMode, pulseStatus;
  final bool motorStatus, pulseDescription;
  final Color pulseColor;
  final int activeSolValveNo;
  final Future<void> Function() onToggleRun;
  final Future<void> Function() onToggleBuzzer;
  final void Function() onTogglePulse;

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;

  @override
  Widget build(BuildContext context) {
    // 권한 설정
    // 1. 현재 선택된 기기 정보 가져오기
    final selected = context.watch<SelectedDevice>().current;

    // 2. AuthService 가져오기
    final auth = context.watch<AuthService>();

    // 3. 현재 기기가 있고, 그 기기에 사용자 권한이 부여되었는지 확인
    bool hasUserAccess = false;
    if (selected != null) {
      hasUserAccess = auth.isUserMode(selected.address, selected.unitId);
    }
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 0),
          child: Column(
            spacing: portrait ? h * 0.02 : h * 0.05,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              //기기이름 표시하기
              Text(
                deviceName,
                style: TextStyle(
                  fontSize: w * 0.05,
                  fontWeight: FontWeight.w500,
                  color: motorStatus
                      ? AppColor.duBlue
                      : Colors.black,
                ),
              ),
              //IP 주소 다음 줄에 표시
              Text(
                "IP: $hostIP [ID: $stationID]",
                style: TextStyle(
                  fontSize: w * 0.03,
                  fontWeight: FontWeight.w300,
                  color: motorStatus
                      ? AppColor.duBlue
                      : Colors.black,
                ),
              ),
              // 기존 디자인 UI
              // 기존 메인 정보 컨테이너
              Container(
                alignment: Alignment.center,
                margin: EdgeInsets.symmetric(
                  horizontal: w * 0.02,
                  vertical: w * 0.01,
                ),
                decoration: BoxDecoration(

                  color: motorStatus ? AppColor.duBlue : Colors.white,
                  border: Border.all(
                    color: AppColor.duBlue,
                    strokeAlign: BorderSide.strokeAlignCenter,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: AspectRatio(
                  aspectRatio: portrait ? 1 : 16 / 9,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    //박스 내 가로축 정렬상태
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        //박스 내 세로축 정렬상태 (간격 균등 배치)
                        children: [
                          SizedBox(
                            width: w * 0.8,
                            child: Row(
                              // 펌웨어 버전
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  "F.W : $fwVer V",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w300,
                                    color: motorStatus
                                        ? Colors.greenAccent
                                        : Colors.black,
                                  ),
                                ),],
                             ),
                            ),

                          SizedBox(
                            width: w * 0.8,
                            child: Row(
                              // 운전시간 및 판넬 모드
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "운전 시간: $operationTime H",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w300,
                                    color: motorStatus
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                                Text(
                                  "모드: $runMode",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w300,
                                    color: motorStatus
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 차압 및 전류 정보
                          Row(
                            spacing: 1,
                            children: [
                              // 차압 및 펄스 설정
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    PageRouteBuilder(
                                      transitionDuration: const Duration(milliseconds: 300),
                                      reverseTransitionDuration: const Duration(milliseconds: 300),
                                      pageBuilder: (context, animation, secondaryAnimation) {
                                        return DpDetailPage(
                                          readRegister: (addr) => readRegister(addr),
                                          writeRegister: (addr, val) => writeRegister(addr, val),
                                        );
                                      },
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                },
                                child: Container(
                                  width: w * 0.6,
                                  height: portrait ? h * 0.14 : h * 0.4,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                    ),
                                  ),
                                  child: Column(
                                    spacing: 0.1,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.end,
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            size: 12,
                                            color: pulseColor,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            pulseStatus,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w100,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                          SizedBox(width: 2),
                                        ],
                                      ),
                                      Row(
                                        spacing: 0.001,
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        crossAxisAlignment:
                                        CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          const SizedBox(width: 1),
                                          Text(
                                            "$diffPressure",
                                            style: TextStyle(
                                              fontFamily: "Digital",
                                              fontSize: 55,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : AppColor.duBlue,
                                            ),
                                          ),
                                          Text(
                                            "mmAq",
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : AppColor.duBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 전류
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    PageRouteBuilder(
                                      transitionDuration: const Duration(milliseconds: 300),
                                      reverseTransitionDuration: const Duration(milliseconds: 300),
                                      pageBuilder: (context, animation, secondaryAnimation) {
                                        return PowerDetailPage(
                                          readRegister: (addr) => readRegister(addr),
                                          writeRegister: (addr, val) => writeRegister(addr, val),
                                        );
                                      },
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                },
                                child: Container(
                                  width: w * 0.3,
                                  height: portrait ? h * 0.14 : h * 0.4,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                    ),
                                  ),
                                  child: Column(
                                    // 전류 표시
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            "$power1",
                                            style: TextStyle(
                                              fontFamily: "Digital",
                                              fontSize: 32,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : AppColor.duBlue,
                                            ),
                                          ),
                                          Text(
                                            "A",
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : AppColor.duBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                        MainAxisAlignment.center,
                                        crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            "$power2",
                                            style: TextStyle(
                                              fontFamily: "Digital",
                                              fontSize: 32,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : AppColor.duBlue,
                                            ),
                                          ),
                                          Text(
                                            "A",
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w600,
                                              color: motorStatus
                                                  ? Colors.white
                                                  : AppColor.duBlue,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // 팬 운전 주파수 및 펄싱
                          Row(
                            //spacing: 5,
                            mainAxisAlignment: MainAxisAlignment.start,
                            //crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset(
                                motorStatus
                                    ? 'assets/images/fan_on.gif'
                                    : 'assets/images/fan_off.png',
                                width: 60,
                                color: motorStatus
                                    ? Colors.white
                                    : Colors.black54,
                                colorBlendMode: BlendMode.srcIn,
                              ),
                              SizedBox(width: w * 0.03),
                              //주파수 표시
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "운전 주파수",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    freqSelectMode == 0 ? "50/60Hz" : " $fanFreq Hz",//(기본주파수)
                                    style: TextStyle(
                                      fontSize: freqSelectMode == 0 ? 10 : 12, // 글자가 길어질 수 있으므로 크기 조절
                                      color: motorStatus ? Colors.white : AppColor.duBlue,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(width: w * 0.01),
                              Image.asset(
                                pulseStatus == "펄스 정지"
                                    ? 'assets/images/c_filter_off.png'
                                    : 'assets/images/c_filter_on.gif',
                                width: 68,
                                color: pulseStatus == "펄스 정지"
                                    ? (motorStatus
                                    ? Colors.white
                                    : Colors.black54)
                                    : (motorStatus
                                    ? Colors.white
                                    : AppColor.duBlue),
                                colorBlendMode: BlendMode.srcIn,
                              ),
                              SizedBox(width: w * 0.03),
                              //펄싱 정보 표시
                              //#27 자동 펄싱 동작 개시 차압값
                              Column(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      activeSolValveNo == 0 ? "정지" : "SOL $activeSolValveNo",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: motorStatus ? AppColor.duBlack : Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "펄싱 차압",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    "$pulseDiff mmAq",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: h * 0.002),
                          // 운전 시작 버튼
                          if (hasUserAccess)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              //crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 20,
                              children: [
                                SizedBox(
                                  width: w * 0.5,
                                  height: portrait ? h * 0.05 : h * 0.12,

                                  child: ElevatedButton(
                                    onPressed: onToggleRun,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: motorStatus
                                          ? Colors.white
                                          : AppColor.duBlue,
                                      shadowColor: Colors.black,
                                      elevation: 2,
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w400,
                                        fontSize: 16,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              motorStatus
                                                  ? Icons.stop
                                                  : Icons.play_arrow,
                                              size: 24,
                                              color: motorStatus
                                                  ? Colors.black
                                                  : Colors.white,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              motorStatus ? '운전 정지' : '운전 시작',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: motorStatus
                                                    ? Colors.black
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // 부저 정지 버튼
                                Container(
                                  width: w * 0.12,
                                  height: portrait ? h * 0.05 : h * 0.12,
                                  decoration: BoxDecoration(
                                    color: motorStatus
                                        ? Colors.white
                                        : AppColor.duBlue,
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: IconButton(
                                    onPressed: onToggleBuzzer,
                                    icon: Icon(
                                      Icons.notifications_off_outlined,
                                      size: 20,
                                      color: motorStatus
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 기존 게이지 그래프 (차압, 전류1, 전류2)
              BgContainer(
                width: w * 0.9,
                height: portrait ? h * 0.15 : h * 0.25,
                child: Padding(
                  padding: EdgeInsetsGeometry.only(bottom: h * 0.01),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    //spacing: w * 0.01,
                    children: [
                      GaugeTile(
                        title: '차압',
                        value: diffPressure.toDouble(),
                        isInt: true,
                        unit: 'mmAq',
                        max: 500,
                        size: w * 0.25,
                        color: AppColor.duBlue,
                        portrait: portrait,
                      ),
                      GaugeTile(
                        title: '전류1',
                        value: power1,
                        isInt: false,
                        unit: 'A',
                        max: 60,
                        size: w * 0.25,
                        color: AppColor.duBlue,
                        portrait: portrait,
                      ),
                      GaugeTile(
                        title: '전류2',
                        value: power2,
                        isInt: false,
                        unit: 'A',
                        max: 60,
                        size: w * 0.25,
                        color: AppColor.duBlue,
                        portrait: portrait,
                      ),
                    ],
                  ),
                ),
              ),
              // 기존 필터 정보 표시
              BgContainer(
                width: w * 0.9,
                height: portrait ? h * 0.07 : h * 0.15,
                radius: w * 0.05,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center, //가로 균형 배치
                  children: [
                    //SizedBox(width: w * 0.1,),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          "필터 사용 시간",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        Row(
                          textBaseline: TextBaseline.alphabetic,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          children: [
                            Text(
                              "$filterTime",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            Text(
                              " 시간",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(width: w * 0.2),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          "필터 교체 횟수",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        Row(
                          textBaseline: TextBaseline.alphabetic,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          children: [
                            Text(
                              "$filterCount",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            Text(
                              " 회",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 로딩 화면
class _LoadingCover extends StatelessWidget {
  const _LoadingCover();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.85),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: AppColor.duBlue),
            SizedBox(height: 12),
            Text('연결 상태 확인 중...', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
