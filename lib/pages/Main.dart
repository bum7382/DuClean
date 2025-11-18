import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:provider/provider.dart';
import 'package:duclean/services/routes.dart';

import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/services/modbus_manager.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/providers/dp_history.dart';

import 'package:duclean/pages/setting/AlarmSetting.dart';
import 'package:duclean/pages/setting/FrequencySetting.dart';
import 'package:duclean/pages/setting/OptionSetting.dart';
import 'package:duclean/pages/setting/PulseSetting.dart';

import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:duclean/services/alarm_store.dart';



class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}



class _MainPageState extends State<MainPage> {
  // 통신 설정
  String _host = "";
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
  var diffPressure = 0;  // 차압
  var power1 = 0.0; // 전류 1
  var power2 = 0.0; // 전류 2

  // 운전시간
  int operationTime = 0;

  String pulseStatus = "펄스 정지";  // 펄스 운전상태
  Color pulseColor = Color(0xffF71041);
  bool motorStatus = false;  // 송풍기 운전상태

  var solValveStatus = false;  // 솔밸브 동작상태

  // 필터 정보 활성화 25.10.31
  var filterTime = 0; // 필터 교체 시간
  var filterCount = 0; // 필터 교체 횟수

  int activeSolValveNo = 0;  // 동작 솔밸브 번호
  var manualPulseStatus; // 수동펄스상태

  var ao1diffPressure; // AO1 차압출력
  var ao2Frequency;  // AO2 주파수 출력

  var alarm1Output;  // 알람 1 출력
  var alarm2Output; // 알람 2 출력
  var alarmBuzzerFlag; // 알람부저플래그
  var alarmCode; // 알람발생코드

  var preAlarm = -1; // 이전 알람
  var isAlarmClear = true;  // 알람 해제 여부
  var currentAlarm = 0;  // 현재 알람
  bool isAlarmChanged = false; // 알람 변경 여부
  var alarmDate; // 알람 발생 시각

  var alarmCount = 0;  // 발생알람개수
  var diStatusValue; // DI 상태값
  var firmwareVersion;  // 펌웨어 버전

// Holding Register(4x)
  final runModeList = ['판넬', '연동', '원격', '통신(RS485)'];  // 동작 설정
  var runMode = "";

  var fanFreq = 0; // #60 송풍기 가동 주파수
  var pulseDiff = 0; // #27 펄스 작동 차압
  var solCount = 0; // #30 동작 솔 밸브 갯수

  bool _loading = true;
  int _pollFailCount = 0;
  static const int _failToShowLoading = 2;


  @override
  void initState() {
    super.initState();
    _inputs = ModbusElementsGroup(
      List.generate(70, (i) => ModbusUint16Register(
        name: 'in_$i',
        type: ModbusElementType.inputRegister,
        address: i,
      )),
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
    _unitId = sel.unitId;
    _deviceName = sel.name;
    _bootStrapped = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 초기 읽기 먼저
      await _readOnEnter();
      // 그 다음 폴링 시작
      await _startPolling();
    });

    /*
    Future.microtask(() async {
      // 초기 읽기 먼저
      await _readOnEnter();
      // 그 다음 폴링 시작
      await _startPolling();
    });*/

    ModbusManager.instance.startAlarmWatch(host: _host, unitId: _unitId, name: _deviceName);
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
    // 초기 진입시 필요한 홀딩들
    final diff = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 27, name: _deviceName);
    final sol = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 33, name: _deviceName);
    final mode = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 34, name: _deviceName);
    final freq = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 60, name: _deviceName);

    if (!mounted) return;
    setState(() {
      runMode = (mode != null && mode >= 0 && mode < runModeList.length) ? runModeList[mode] : '';
      fanFreq = freq ?? 0;
      pulseDiff = diff ?? 0;
      solCount = sol ?? 0;
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
      if (e.clearedTsMs == null) open++;   // 최신이 미해제면 그 기기는 "알람 진행 중"
    }

    if (!mounted) return;
    setState(() => _globalAlarmOpenCount = open);
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
        final man = (_inputs[54] as ModbusUint16Register).value?.toInt() ?? 0;
        return man == 0 ? "수동 펄스" : "전자동 펄스";
      case 3:
        pulseColor = Color(0xff4BFC06);
        return "추가 펄스";
      default:
        pulseColor = Color(0xffF71041);
        return "알수없음($code)";
    }
  }

  // Read Input Register 함수
  Future<void> _startPolling() async {
    // 최초 1회만 연결 확보(실패하면 throw되어 catch에서 다음 틱에 재시도)
    _client ??= await ModbusManager.instance.ensureConnected(
      context, host: _host, unitId: _unitId, name: _deviceName
    );

    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) async {
      if (!mounted) return;
      if (_pollingBusy) return;       // ⬅ 재진입 방지
      _pollingBusy = true;
      try {
        // 연결 확인: 끊겼으면 이 시점에만 재연결 시도
        if (_client == null || !(_client!.isConnected)) {
          _client = await ModbusManager.instance.ensureConnected(
            context, host: _host, unitId: _unitId, name: _deviceName
          );
        }

        await _client!.send(_inputs.getReadRequest());

        final dp   = (_inputs[0]  as ModbusUint16Register).value?.toInt() ?? 0;
        final p1   = ((_inputs[1]  as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        final p2   = ((_inputs[2]  as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        final opHi = (_inputs[11] as ModbusUint16Register).value?.toInt() ?? 0;
        final opLo = (_inputs[12] as ModbusUint16Register).value?.toInt() ?? 0;
        final pul  = (_inputs[13] as ModbusUint16Register).value?.toInt() ?? 0;
        final run  = (_inputs[14] as ModbusUint16Register).value?.toInt() ?? 0;
        final solNumber  = (_inputs[18] as ModbusUint16Register).value?.toInt() ?? 0;

        final curAlarm = (_inputs[25] as ModbusUint16Register).value?.toInt() ?? 0;
        debugPrint(curAlarm.toString());
        final alarmCnt = (_inputs[40] as ModbusUint16Register).value?.toInt() ?? 0;

        final filterUsed   = (_inputs[16] as ModbusUint16Register).value?.toInt() ?? 0;
        final filterChange = (_inputs[17] as ModbusUint16Register).value?.toInt() ?? 0;

        context.read<ConnectionRegistry>().setAlarmCode(_host, _unitId, curAlarm);
        context.read<DpHistory>().addPoint(dp.toDouble());

        if (!mounted) return;
        setState(() {
          diffPressure   = dp;
          power1         = p1;
          power2         = p2;
          operationTime  = ((opHi & 0xFFFF) << 16) | (opLo & 0xFFFF);
          pulseStatus    = pulseStatusLabel(pul);
          motorStatus    = (run != 0);
          currentAlarm   = curAlarm;
          alarmCount     = alarmCnt;
          filterTime     = filterUsed;
          filterCount    = filterChange;
          _pollFailCount = 0;
          activeSolValveNo = solNumber;
          _loading = false;
        });
      } catch (e) {
        // 실패 시: 로딩 표시 및 다음 틱에서 자동 재시도
        if (!mounted) return;
        setState(() {
          _pollFailCount++;
          if (_pollFailCount >= _failToShowLoading) {
            _loading = true;
          }
        });
        debugPrint('폴링 실패: $e');

        // 소켓이 비정상일 수 있으므로 다음 틱 전에 정리
        try { await _client?.disconnect(); } catch (_) {}
        _client = null;
      } finally {
        _pollingBusy = false;
      }
    });
  }


  Future<bool> writeRegister(int address, int value) {
    return ModbusManager.instance.writeHolding(
        context, host: _host, unitId: _unitId, name: _deviceName, address: address, value: value);
  }

  Future<int?> readRegister(int address) {
    return ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, name: _deviceName, address: address);
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
    Future<void> _toggleBuzzer() async {
      try{
        if (!mounted) return;
        await writeRegister(1, 1);
      }
      catch(e){
        debugPrint('쓰기 실패: $e');
      }
    }



    return Scaffold(
      backgroundColor: AppColor.bg,

      appBar: AppBar(
        backgroundColor: AppColor.duBlue,
        centerTitle: true,
        title: const SizedBox.shrink(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    // 알람 아이콘 onPressed
                    Navigator.of(context).pushNamed(
                      Routes.alarmPage,
                      arguments: <String, dynamic>{
                        'date': alarmAt,
                        'name': _deviceName,
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
                            _globalAlarmOpenCount > 0 ? Icons.notifications_on : Icons.notifications,
                            size: 30,
                            color: _globalAlarmOpenCount > 0 ? Colors.red : Colors.white,
                          ),
                        ),
                        // 알람 개수
                        if (_globalAlarmOpenCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              constraints: const BoxConstraints(minWidth: 18),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white, width: 1.2),
                              ),
                              child: Text(
                                _globalAlarmOpenCount.toString(),
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
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.menu, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 4),
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
                  //mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  //crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/images/logo_white.png', width: 95),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        AppConst.version,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
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
        selectedItemColor: AppColor.duBlue,
        currentIndex: _currentIndex,
          onTap: (i) async {
            if (i == _currentIndex) return;
            setState(() => _currentIndex = i);
            // 홈(메인) 탭으로 돌아올 때 최신값 재읽기
            if (i == 0) {
              await _readOnEnter();
            }
          },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.tune), label: '주파수 설정'),
          BottomNavigationBarItem(icon: Icon(Symbols.valve), label: '펄스 설정'),
          BottomNavigationBarItem(icon: Icon(Symbols.notification_settings), label: '알람 설정'),
          BottomNavigationBarItem(icon: Icon(Icons.handyman_outlined), label: '옵션 설정'),
        ]
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              _HomeTab(
                w: context.screenWidth,
                h: context.screenHeight,
                portrait: context.isPortrait,
                deviceName: _deviceName,
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
                onToggleRun: _toggleRun,        // MainPage의 함수 전달
                onToggleBuzzer: _toggleBuzzer,  // MainPage의 함수 전달
              ),
              FrequencySettingPage(
                readRegister: (addr) => readRegister(addr),
                writeRegister: (addr, val) => writeRegister(addr, val),
              ),  // 주파수 설정 탭
              PulseSettingPage(
                readRegister: (addr) => readRegister(addr),
                writeRegister: (addr, val) => writeRegister(addr, val),
              ),      // 펄스 설정 탭
              AlarmSettingPage(              // 알람 설정 탭
                readRegister: (addr) => readRegister(addr),
                writeRegister: (addr, val) => writeRegister(addr, val),
              ),
              OptionSettingPage(
                readRegister: (addr) => readRegister(addr),
                writeRegister: (addr, val) => writeRegister(addr, val),
                onRunModeChanged: (label) {           // ⬅ 추가
                  if (!mounted) return;
                  setState(() { runMode = label; });  // 홈 탭의 표시 즉시 갱신
                },
              ),     // 옵션 설정 탭
            ],
          ),
          if (_loading && _currentIndex == 0) const _LoadingCover()
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
  });

  final double w, h;
  final bool portrait;
  final String deviceName;
  final int diffPressure, operationTime, fanFreq, pulseDiff, solCount, alarmCount;
  final int filterTime;
  final int filterCount;
  final double power1, power2;
  final String runMode, pulseStatus;
  final bool motorStatus;
  final Color pulseColor;
  final int activeSolValveNo;
  final Future<void> Function() onToggleRun;
  final Future<void> Function() onToggleBuzzer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Center(
        //child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 운전 조작 관련 패널
              Container(
                alignment: Alignment.center,
                margin: EdgeInsets.symmetric(horizontal: w*0.02, vertical: w*0.05),
                decoration: BoxDecoration(
                  color: motorStatus ? AppColor.duBlue : Colors.white,
                  border: Border.all(color: AppColor.duBlue, strokeAlign: BorderSide.strokeAlignCenter, width: 2),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child:
                AspectRatio(
                  aspectRatio: portrait ? 1 : 16/9,
                  child:
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center, //박스 내 가로축 정렬상태
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,//박스 내 세로축 정렬상태
                        children: [
                          Text(deviceName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: motorStatus ? Colors.white : AppColor.duBlue),),
                          const SizedBox(height: 5),
                          SizedBox(
                            width: w * 0.8,
                            child: Row( // 운전시간 및 판넬 모드
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("운전 시간: $operationTime H", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: motorStatus ? Colors.white : Colors.black),),
                                Text("모드: $runMode", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: motorStatus ? Colors.white : Colors.black)),
                              ],
                            ),
                          ),

                          // 차압 및 전류 정보
                          Row(
                            spacing: 2,
                            children: [
                              // 차압 및 펄스 설정
                              GestureDetector(
                                onTap:(){
                                  Navigator.of(context).pushNamed(Routes.dpDetailPage);
                                },
                                child: Container(
                                  width: w * 0.6,
                                  height: portrait ? h * 0.15 : h * 0.18,
                                  margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                                  decoration: BoxDecoration(
                                      border:Border.all(color: motorStatus ? Colors.white : AppColor.duBlue)
                                  ),
                                  child:
                                  Column(
                                    //spacing: 0.05,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Icon(Icons.circle,
                                              size: 12,
                                              color: pulseColor),
                                          SizedBox(width: 5,),
                                          Text(pulseStatus, style:TextStyle(fontSize: 12, fontWeight: FontWeight.w100 ,color: motorStatus ? Colors.white : Colors.black)),
                                          SizedBox(width: 5,)
                                        ],
                                      ),
                                      Row(
                                        spacing: 0.15,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          const SizedBox(width: 5),
                                          Text("$diffPressure", style: TextStyle(fontFamily: "Digital", fontSize: 55, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                          Text("mmAq", style: TextStyle(fontSize:15, fontWeight: FontWeight.w600, color: motorStatus ? Colors.white : AppColor.duBlue))
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 전류
                              Container(
                                width: w * 0.3,
                                height: portrait ? h * 0.15 : h * 0.18,
                                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                                decoration: BoxDecoration(
                                  border:Border.all(color: motorStatus ? Colors.white : AppColor.duBlue)
                                ),
                                child:
                                Column( // 전류 표시
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text("$power1", style: TextStyle(fontFamily: "Digital", fontSize: 32, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                        Text("A", style: TextStyle(fontSize:20, fontWeight: FontWeight.w600, color: motorStatus ? Colors.white : AppColor.duBlue))
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text("$power2", style: TextStyle(fontFamily: "Digital", fontSize: 32, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                        Text("A", style: TextStyle(fontSize:20, fontWeight: FontWeight.w600, color: motorStatus ? Colors.white : AppColor.duBlue))
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: h* 0.02),
                          // 팬 운전 주파수 및 펄싱
                          Row(
                            spacing: 5,
                            mainAxisAlignment: MainAxisAlignment.start,
                            //crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Image.asset(motorStatus ? 'assets/images/fan_on.gif' : 'assets/images/fan_off.png', width: 60,
                                color: motorStatus? Colors.white : Colors.black54,
                                colorBlendMode: BlendMode.srcIn,),
                              SizedBox(width: w* 0.005),
                              //주파수 표시
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text("운전 주파수", style: TextStyle(fontSize: 13, color: motorStatus ? Colors.white : AppColor.duBlue, fontWeight: FontWeight.w600),),
                                  Text(" $fanFreq Hz", style: TextStyle(fontSize: 12, color: motorStatus ? Colors.white : AppColor.duBlue),)
                                ],
                              ),
                              SizedBox(width: w* 0.05),
                              Image.asset(pulseStatus == "펄스 정지" ? 'assets/images/c_filter_off.png' : 'assets/images/c_filter_on.gif', width: 68,
                                color: pulseStatus == "펄스 정지" ? (motorStatus ? Colors.white : Colors.black54) : (motorStatus ? Colors.white : AppColor.duBlue),
                                colorBlendMode: BlendMode.srcIn,),
                              SizedBox(width: w* 0.005),
                              //펄싱 정보 표시
                              //#27 자동 펄싱 동작 개시 차압값
                              Column(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: motorStatus ? Colors.white : AppColor.duBlue,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    child: Text("SOL $activeSolValveNo", style: TextStyle( fontSize: 11, color: motorStatus ? AppColor.duBlue : Colors.white,
                                        fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  SizedBox(height: 4,),
                                  Text("펄싱 차압", style: TextStyle(fontSize: 13, color: motorStatus ? Colors.white : AppColor.duBlue,
                                      fontWeight: FontWeight.w600),textAlign: TextAlign.center,),
                                  Text("$pulseDiff mmAq", style: TextStyle(fontSize: 11, color: motorStatus ? Colors.white : AppColor.duBlue)),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: h* 0.02),
                          // 운전 시작 버튼
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            //crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 50,
                            children: [
                              SizedBox(
                                width: w * 0.5,
                                height: portrait ? h * 0.05 : h * 0.12,

                                child:
                                ElevatedButton(
                                  onPressed: onToggleRun,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: motorStatus ? Colors.white : AppColor.duBlue,
                                    shadowColor: Colors.black,
                                    elevation: 2,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(motorStatus ? Icons.stop : Icons.play_arrow,
                                              size: 24,
                                              color: motorStatus ? Colors.black : Colors.white),
                                          const SizedBox(width: 4),
                                          Text(
                                            motorStatus ? '운전 정지' : '운전 시작',
                                            style: TextStyle(
                                              fontSize: 20,
                                              color: motorStatus ? Colors.black : Colors.white,
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
                              // 부저 정지 버튼
                              Container(
                                width: w * 0.12,
                                height: portrait ? h * 0.05 : h * 0.12,
                                decoration: BoxDecoration(
                                  color: motorStatus ? Colors.white : AppColor.duBlue,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child:
                                IconButton(
                                  onPressed: onToggleBuzzer,
                                  icon: Icon(Icons.notifications_off_outlined,
                                      size: 20,
                                      color: motorStatus ? Colors.black : Colors.white
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
              // 게이지 그래프 (차압, 전류1, 전류2)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.01),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child:
                Padding(
                  padding: EdgeInsets.fromLTRB(0, 30, 0, 0),
                  child:
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: GaugeTile(title: '차압',  valueStr: diffPressure.toString(), unit: 'mmAq', max: 500)),
                      Expanded(child: GaugeTile(title: '전류1', valueStr: power1.toString(),       unit: 'A',     max: 60)),
                      Expanded(child: GaugeTile(title: '전류2', valueStr: power2.toString(),       unit: 'A',     max: 60)),
                    ],
                  ),
                ),
              ),

              // 필터 정보 표시
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.01),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child:
                Padding(
                  padding: EdgeInsets.fromLTRB(0, 15, 0, 15),
                  child:
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      SizedBox(width: w * 0.1,),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("필터 사용시간:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),),
                          Row(
                            textBaseline: TextBaseline.alphabetic,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            children: [
                              Text("$filterTime", style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),),
                              Text("시간", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(width: w * 0.27,),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("필터 교체횟수:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),),
                          Row(
                            textBaseline: TextBaseline.alphabetic,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            children: [
                              Text("$filterCount", style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),),
                              Text("회", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),




            ],
          ),
        ),
      ),
    );
  }
}





class GaugeTile extends StatelessWidget {
  const GaugeTile({
    super.key,
    required this.title,
    required this.valueStr,
    required this.unit,
    required this.max,
  });

  final String title, valueStr, unit;
  final double max;

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(valueStr) ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = w * 0.8;
        final axis = w * 0.13;
        final titleFont = w * 0.10;
        final valueFont = w * 0.10;
        final unitFont = w * 0.075;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(fontSize: titleFont, fontWeight: FontWeight.w800, color: AppColor.duBlue)),
            SizedBox(
              height: h,
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    startAngle: 180,
                    endAngle: 0,
                    minimum: 0,
                    maximum: max,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: AxisLineStyle(thickness: axis),
                    pointers: <GaugePointer>[
                      RangePointer(value: value, color: AppColor.duBlue, width: axis),
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        angle: -90,
                        positionFactor: 0.1,
                        widget: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(valueStr, style: TextStyle(fontWeight: FontWeight.bold, fontSize: valueFont, color: AppColor.duBlue)),
                            Text(unit, style: TextStyle(fontSize: unitFont, color: AppColor.duBlue)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
        color: Colors.white.withValues(alpha: 0.85), // 배경 희미하게
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: AppColor.duBlue,),
            SizedBox(height: 12),
            Text('연결 상태 확인 중...', style: TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
