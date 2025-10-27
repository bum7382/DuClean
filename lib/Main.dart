import 'package:duclean/Alarm.dart';
import '/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duclean/res/Constants.dart';
import 'dart:async';

import 'package:syncfusion_flutter_gauges/gauges.dart';

late SharedPreferences _prefs;

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}



class _MainPageState extends State<MainPage> {
  // 통신 설정
  final String _host = "192.168.10.190";
  final int _unitId = 1;

  // 소켓 & 폴링 상태
  ModbusClientTcp? _client;
  Timer? _poller;
  bool _connecting = false;
  int _reconnectAttempt = 0;

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

  var filterTime = 0; // 필터 교체 시간
  var filterCount = 0; // 필터 교체 횟수

  var activeSolValveNo;  // 동작 솔밸브 번호
  var manualPulseStatus; // 수동펄스상태

  var ao1diffPressure; // AO1 차압출력
  var ao2Frequency;  // AO2 주파수 출력

  var alarm1Output;  // 알람 1 출력
  var alarm2Output; // 알람 2 출력
  var alarmBuzzerFlag; // 알람부저플래그
  var alarmCode; // 알람발생코드

  var preAlarm = -1; // 이전 알람
  var currentAlarm = 0;  // 현재 알람
  bool isAlarmChanged = false; // 알람 변경 여부
  var alarmDate; // 알람 발생 시각

  var alarmCount;  // 발생알람개수
  var diStatusValue; // DI 상태값
  var firmwareVersion;  // 펌웨어 버전

  final runModeList = ['판넬', '연동', '원격', '통신(RS485)'];  // 동작 설정
  var runMode = '판넬';

  static const _kAlarmCodeKey = 'alarm_current_code';
  static const _kAlarmDateKey = 'alarm_current_date_ms';

  @override
  // 타이머 시작
  void initState() {
    super.initState();
    _inputs = ModbusElementsGroup(
      List.generate(70, (i) =>
          ModbusUint16Register(
            name: 'in_$i',
            type: ModbusElementType.inputRegister,
            address: i,
          )),
    );
    _initPrefsAndStart();
  }

  Future<void> _initPrefsAndStart() async {
    _prefs = await SharedPreferences.getInstance();
    await _connectAndStartPolling();
    await _readOnEnter();
  }

  // 첫 진입 시 R/W 레지스터 값 읽어서 초기화
  Future<void> _readOnEnter() async {
    final mode = await readRegister(34);
    if (mounted) {
      setState(() {
        runMode = mode != null? runModeList[mode] : '판넬';
      });
    }
  }

  // 연결 종료
  @override
  void dispose() {
    _poller?.cancel();
    _poller = null;
    _safeDisconnect();
    super.dispose();
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
        return "수동 펄스";
      case 3:
        pulseColor = Color(0xff4BFC06);
        return "추가 펄스";
      default:
        pulseColor = Color(0xffF71041);
        return "알수없음($code)";
    }
  }

  // Read Input Register 함수
  Future<void> _connectAndStartPolling() async {
    // 연결
    await _ensureConnected();
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!mounted) return;
      // 끊겼으면 재연결
      if (!await _ensureConnected()) return;

      try {
        await _client!.send(_inputs.getReadRequest());

        // 값 꺼내기
        final dp = (_inputs[0]  as ModbusUint16Register).value?.toInt() ?? 0; // 차압
        final p1 = ((_inputs[1]  as ModbusUint16Register).value?.toDouble() ?? 0) / 10; // 전류 1
        final p2 = ((_inputs[2]  as ModbusUint16Register).value?.toDouble() ?? 0) / 10; // 전류 2

        // 운전시간
        final opHi = (_inputs[11]  as ModbusUint16Register).value?.toInt() ?? 0;  // 상위
        final opLo = (_inputs[12]  as ModbusUint16Register).value?.toInt() ?? 0;  // 하위

        final pul = (_inputs[13]  as ModbusUint16Register).value?.toInt() ?? 0;   // 펄스 모드 상태

        final runFlag = (_inputs[14] as ModbusUint16Register).value?.toInt() ?? 0;  // 송풍기 운전 상태

        final alarmFlag = (_inputs[24] as ModbusUint16Register).value?.toInt() ?? 0;  // 알람부저 플래그
        final curAlarm = (_inputs[25] as ModbusUint16Register).value?.toInt() ?? 0;  // 알람 이력

        if (alarmFlag != 0) {
          if((curAlarm != 0) && (preAlarm != curAlarm)){
            alarmDate = DateTime.now();
            await _prefs.setInt(_kAlarmCodeKey, curAlarm);
            await _prefs.setInt(_kAlarmDateKey, (alarmDate as DateTime).millisecondsSinceEpoch);
            preAlarm = curAlarm;
          }
          else if(curAlarm == 0){
            preAlarm = curAlarm;
          }
        }


        if (!mounted) return;

        setState(() {
          // 상태 변경
          diffPressure = dp;
          power1 = p1;
          power2 = p2;
          operationTime = ((opHi & 0xFFFF) << 16) | (opLo & 0xFFFF);
          pulseStatus = pulseStatusLabel(pul);
          motorStatus = (runFlag != 0);
          currentAlarm = curAlarm;

          // 성공 시 백오프 리셋
          _reconnectAttempt = 0;
        });
      } catch (e) {
        // 다음 틱에서 재시도
        debugPrint('폴링 실패: $e');
      }
    });
  }

  // 연결 보장 함수
  Future<bool> _ensureConnected() async {
    try {
      if (_client != null && _client!.isConnected) return true;
    } catch (_) {}

    if (_connecting) return false;
    _connecting = true;

    try {
      await _safeDisconnect(); // 이전 소켓 정리
      final c = ModbusClientTcp(_host, unitId: _unitId);
      await c.connect();
      _client = c;
      _connecting = false;
      debugPrint('Modbus 연결 성공');
      return true;
    } catch (e) {
      _connecting = false;
      _client = null;
      _reconnectAttempt += 1;
      final delayMs = _backoffMs(_reconnectAttempt);
      debugPrint('Modbus 연결 실패: $e → ${delayMs}ms 후 재시도 예정');
      // 다음 타이머 틱에서 재시도
      return false;
    }
  }

  // 연결 해제
  Future<void> _safeDisconnect() async {
    try {
      if (_client != null) {
        await _client!.disconnect();
      }
    } catch (_) {
      // ignore
    } finally {
      _client = null;
    }
  }

  int _backoffMs(int attempt) {
    final base = 500 * (1 << (attempt - 1));
    return base.clamp(500, 8000);
  }

  /// Modbus 쓰기 함수
  Future<bool> writeRegister(int address, int value) async {
    // 연결 보장
    if (!await _ensureConnected()) {
      debugPrint("Modbus 쓰기 실패: 연결되지 않음");
      return false;
    }

    try {
      final register = ModbusInt16Register(
        name: "Holding($address)",
        type: ModbusElementType.holdingRegister, // FC06: Write Single Holding Register
        address: address,
      );

      await _client!.send(register.getWriteRequest(value));
      _reconnectAttempt = 0;
      return true;
    } catch (e) {
      debugPrint("Modbus 쓰기 에러: $e");
      return false;
    }
  }

  // Modbus 읽기 함수
  Future<int?> readRegister(int address) async {
    if (!await _ensureConnected()) {
      debugPrint("Modbus 읽기 실패: 연결되지 않음");
      return null;
    }

    try {
      final register = ModbusInt16Register(
        name: "Holding($address)",
        type: ModbusElementType.holdingRegister, // FC03
        address: address,
      );

      await _client!.send(register.getReadRequest());

      _reconnectAttempt = 0; // 성공 시 백오프 리셋
      return register.value?.toInt();
    } catch (e) {
      debugPrint("Modbus 읽기 에러: $e");
      return null;
    }
  }

  // 게이지 그래프 속성
  Widget _gaugeTile(String title, String valueStr, String unit, double max) {
    final value = double.tryParse(valueStr) ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth; // 1/3 칸의 실제 폭
        final h = w * 0.8;  // 반원 높이
        final axis = w * 0.13;  // 원 두께
        final pointer = axis; // 포인터 두께
        final markerH = w * 0.05;  // 포인터 세로 길이
        final markerW = w * 0.05;  // 포인터 가로 길이
        final titleFont = w * 0.10; // 제목
        final valueFont = w * 0.10; // 값
        final unitFont = w * 0.075; // 단위

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
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
                          RangePointer(
                            value: value,
                            color: AppColor.duBlue,
                            width: axis,
                          ),
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
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {

    // 화면 크기
    Size screenSize = MediaQuery.of(context).size;
    var screenWidth = screenSize.width;
    var screenHeight = screenSize.height;

    // 세로 모드 여부
    var isPortrait = screenWidth < screenHeight ? true : false;

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
      backgroundColor: const Color(0xfff6f6f6),

      appBar: AppBar(
        backgroundColor: AppColor.duBlue,
        centerTitle: true,
        title: const SizedBox.shrink(), // 기본 title은 비움(중앙 정렬을 Stack으로 직접 제어)
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // actions 가장자리 붙는 느낌을 줄이기 위해 Padding 추가
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      Routes.alarmPage,
                      arguments: <String, dynamic>{'date': alarmDate, "name": "AP-500"},
                    );
                  },
                  icon: const Icon(Icons.notifications, color: Colors.white, size: 30),
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
        // 완전 중앙 보정을 위해 flexibleSpace에 Stack 사용
        flexibleSpace: SafeArea(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/logo_white.png', width: 100),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        AppConst.version,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 운전 조작 관련 패널
              Container(
                alignment: Alignment.center,
                margin: EdgeInsets.symmetric(horizontal: screenWidth*0.05, vertical: screenWidth*0.1),
                decoration: BoxDecoration(
                  color: motorStatus ? AppColor.duBlue : Colors.white,
                  border: Border.all(color: AppColor.duBlue, strokeAlign: BorderSide.strokeAlignOutside, width: 2),
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
                    aspectRatio: isPortrait ? 1 : 16/9,
                    child:
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            children: [
                              const SizedBox(height: 8),
                              SizedBox(
                                width: screenWidth * 0.75,
                                child: Row( // 운전시간 및 판넬 모드
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("운전 시간: $operationTime H", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: motorStatus ? Colors.white : Colors.black),),
                                    Text("모드: $runMode", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: motorStatus ? Colors.white : Colors.black)),
                                  ],
                                ),
                              ),

                              // 차압 및 전류 정보
                              Row(
                                spacing: 3,
                                children: [
                                  // 차압 및 펄스 설정
                                  Container(
                                    width: screenWidth * 0.5,
                                    height: isPortrait ? screenHeight * 0.15 : screenHeight * 0.4,
                                    margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 20),
                                    decoration: BoxDecoration(
                                      border:Border.all(color: motorStatus ? Colors.white : AppColor.duBlue)
                                    ),
                                    child:
                                      Column(
                                      spacing: 5,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Icon(Icons.circle,
                                                size: 14,
                                                color: pulseColor),
                                            SizedBox(width: 5,),
                                            Text(pulseStatus, style:TextStyle(fontSize: 12, fontWeight: FontWeight.w100 ,color: motorStatus ? Colors.white : Colors.black)),
                                            SizedBox(width: 10,)
                                          ],
                                        ),
                                        Row(
                                          spacing: 10,
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            const SizedBox(width: 5),
                                            Text("$diffPressure", style: TextStyle(fontFamily: "Digital", fontSize: 50, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                            Text("mmAq", style: TextStyle(fontSize:14, fontWeight: FontWeight.w500, color: motorStatus ? Colors.white : AppColor.duBlue))
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 전류
                                  Container(
                                    width: screenWidth * 0.25,
                                    height: isPortrait ? screenHeight * 0.15 : screenHeight * 0.4,
                                    margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 20),
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
                                            Text("$power1", style: TextStyle(fontFamily: "Digital", fontSize: 35, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                            Text("A", style: TextStyle(fontSize:20, fontWeight: FontWeight.w600, color: motorStatus ? Colors.white : AppColor.duBlue))
                                          ],
                                        ),
                                          Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text("$power2", style: TextStyle(fontFamily: "Digital", fontSize: 35, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                            Text("A", style: TextStyle(fontSize:20, fontWeight: FontWeight.w600, color: motorStatus ? Colors.white : AppColor.duBlue))
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              // 주파수 및 펄싱
                              Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Container(
                                    width: screenWidth * 0.38,
                                    height: isPortrait ? screenHeight * 0.1 : screenHeight * 0.3,
                                    decoration: BoxDecoration(border: Border.all(color: AppColor.duBlue, width: 1)),
                                    child: Row(
                                      children: [
                                        Image.asset('assets/images/Fan_1.gif', width: 100),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: screenWidth * 0.38,
                                    height: isPortrait ? screenHeight * 0.1 : screenHeight * 0.3,
                                    decoration: BoxDecoration(border: Border.all(color: AppColor.duBlue, width: 1)),
                                  ),
                                ],
                              ),
                              // 운전 시작 버튼
                              Row(
                                spacing: 10,
                                children: [
                                  SizedBox(
                                    width: screenWidth * 0.55,
                                    height: isPortrait ? screenHeight * 0.065 : screenHeight * 0.15,
                                    child:
                                      ElevatedButton(
                                        onPressed: _toggleRun,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: motorStatus ? Colors.white : AppColor.duBlue,
                                          shadowColor: Colors.black,
                                          elevation: 2,
                                          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 20),
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
                                    width: screenWidth * 0.15,
                                    height: isPortrait ? screenHeight * 0.065 : screenHeight * 0.15,
                                    decoration: BoxDecoration(
                                      color: motorStatus ? Colors.white : AppColor.duBlue,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child:
                                      IconButton(
                                          onPressed: _toggleBuzzer,
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
                      color: Colors.black.withOpacity(0.01),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child:
                  Padding(
                    padding: EdgeInsetsGeometry.fromLTRB(0, 30, 0, 0),
                    child:
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _gaugeTile('차압', diffPressure.toString(), 'mmAq',500)),
                          Expanded(child: _gaugeTile('전류1', power1.toString(), 'A', 60)),
                          Expanded(child: _gaugeTile('전류2', power2.toString(), 'A', 60)),
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
