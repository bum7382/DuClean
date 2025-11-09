import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:provider/provider.dart';
import '../routes.dart';

import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'services/modbus_manager.dart';
import '../providers/selected_device.dart'; // SelectedDevice, ConnectionRegistry

import 'package:syncfusion_flutter_gauges/gauges.dart';


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

  var activeSolValveNo;  // 동작 솔밸브 번호
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
  var runMode = '판넬';

  var fanFreq = 0; // #60 송풍기 가동 주파수
  var pulseDiff = 0; // #27 펄스 작동 차압
  var solCount = 0; // #30 동작 솔 밸브 갯수


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

    _startPolling();
    _readOnEnter();
  }

  @override
  void dispose() {
    _poller?.cancel();
    _poller = null;
    // 연결 해제
    ModbusManager.instance.disconnect(context, host: _host, unitId: _unitId);
    super.dispose();
  }

  // 첫 진입 시 R/W 레지스터 값 읽어서 초기화
  Future<void> _readOnEnter() async {
    // 초기 진입시 필요한 홀딩들
    final diff = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 27);
    final sol = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 33);
    final mode = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 34);
    final freq = await ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: 60);

    if (!mounted) return;
    setState(() {
      runMode = (mode != null && mode >= 0 && mode < runModeList.length)
          ? runModeList[mode]
          : '판넬';
      fanFreq = freq ?? 0;
      pulseDiff = diff ?? 0;
      solCount = sol ?? 0;
    });
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
  Future<void> _startPolling() async {
    // 최초 연결 보장
    _client = await ModbusManager.instance.ensureConnected(
        context, host: _host, unitId: _unitId);

    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!mounted) return;

      try {
        // 연결 보장(재연결 포함)
        _client = await ModbusManager.instance.ensureConnected(
            context, host: _host, unitId: _unitId);

        await _client!.send(_inputs.getReadRequest());

        final dp   = (_inputs[0]  as ModbusUint16Register).value?.toInt() ?? 0;
        final p1   = ((_inputs[1]  as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        final p2   = ((_inputs[2]  as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
        final opHi = (_inputs[11] as ModbusUint16Register).value?.toInt() ?? 0;
        final opLo = (_inputs[12] as ModbusUint16Register).value?.toInt() ?? 0;
        final pul  = (_inputs[13] as ModbusUint16Register).value?.toInt() ?? 0;
        final run  = (_inputs[14] as ModbusUint16Register).value?.toInt() ?? 0;

        final curAlarm = (_inputs[25] as ModbusUint16Register).value?.toInt() ?? 0;
        final alarmCnt = (_inputs[40] as ModbusUint16Register).value?.toInt() ?? 0;

        final filterUsed   = (_inputs[16] as ModbusUint16Register).value?.toInt() ?? 0;
        final filterChange = (_inputs[17] as ModbusUint16Register).value?.toInt() ?? 0;

        // ✅ 알람은 Registry에 반영(변경시에만 notify)
        context.read<ConnectionRegistry>()
            .setAlarmCode(_host, _unitId, curAlarm);

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
        });
      } catch (e) {
        // 실패 시 다음 틱에서 재시도(ensureConnected가 재연결 시도)
        debugPrint('폴링 실패: $e');
      }
    });
  }

  Future<bool> writeRegister(int address, int value) {
    return ModbusManager.instance.writeHolding(
        context, host: _host, unitId: _unitId, address: address, value: value);
  }

  Future<int?> readRegister(int address) {
    return ModbusManager.instance.readHolding(
        context, host: _host, unitId: _unitId, address: address);
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
                        'date': alarmAt,           // ← 레지스트리 시각 전달
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
                            alarmCount > 0 ? Icons.notifications_on : Icons.notifications,
                            size: 30,
                            color: alarmCount > 0 ? Colors.red : Colors.white,
                          ),
                        ),
                        // 알람 개수
                        if (alarmCount > 0)
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
                                alarmCount.toString(),
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

      body:  Center(
        //child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 0),
          child: Column(
            //mainAxisAlignment: MainAxisAlignment.start,
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
                          const SizedBox(height: 5),
                          SizedBox(
                            width: w * 0.8,
                            child: Row( // 운전시간 및 판넬 모드
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("운전 시간: $operationTime H", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: motorStatus ? Colors.white : Colors.black),),
                                Text("모드: $runMode", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: motorStatus ? Colors.white : Colors.black)),
                                /*DropdownButton(
                                      value: runMode,
                                      items: runModeList
                                          .map((e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(e),
                                      )).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          switch(value){
                                            case '판넬': writeRegister(34, 0);
                                            case '연동': writeRegister(34, 1);
                                            case '원격': writeRegister(34, 2);
                                            case '통신(RS485)': writeRegister(34, 3);
                                          }
                                          runMode = value!;

                                        });
                                      },
                                    ),*/
                              ],
                            ),
                          ),

                          // 차압 및 전류 정보
                          Row(
                            spacing: 2,
                            children: [
                              // 차압 및 펄스 설정
                              Container(
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

                          // 팬 운전 주파수 및 펄싱
                          Row(
                            spacing: 5,
                            mainAxisAlignment: MainAxisAlignment.start,
                            //crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: w * 0.2,
                                height: portrait ? h * 0.1 : h * 0.15,
                                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                                //decoration: BoxDecoration(color: Colors.white),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset('assets/images/fan_on.gif', width: 60,
                                      color: motorStatus? Colors.white : AppColor.duBlue,
                                      colorBlendMode: BlendMode.srcIn,), //on
                                    //Image.asset('assets/images/Fan_1.gif', width: 60,), // off

                                  ],
                                ),
                              ),
                              //주파수 표시
                              Container(
                                width: w * 0.22,
                                height: portrait ? h * 0.1 : h * 0.15,
                                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text("운전 주파수", style: TextStyle(fontSize: 12, color: motorStatus ? Colors.white : AppColor.duBlue),),

                                    Text(" $fanFreq Hz", style: TextStyle(fontSize: 12, color: motorStatus ? Colors.white : AppColor.duBlue),)
                                  ],
                                ),

                              ),
                              Container(
                                width: w * 0.2,
                                height: portrait ? h * 0.1 : h * 0.15,
                                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                                //decoration: BoxDecoration(color: Colors.white),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [

                                    Image.asset('assets/images/c_filter_on.gif', width: 68,
                                      color: motorStatus? Colors.white : AppColor.duBlue,
                                      colorBlendMode: BlendMode.srcIn,), //on
                                    //Image.asset('assets/images/c_filter_off.png', width: 60,), //off


                                  ],
                                ),
                              ),

                              //펄싱 정보 표시
                              Container(
                                width: w * 0.22,
                                height: portrait ? h * 0.1 : h * 0.15,
                                margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                                child: Column(
                                  //mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    //#27 자동 펄싱 동작 개시 차압값
                                    Text("펄싱 차압   $pulseDiff mmAq", style: TextStyle(fontSize: 11, color: motorStatus ? Colors.white : AppColor.duBlue),),
                                    //#33 솔밸브 갯수
                                    Text("솔밸브 갯수   $solCount 개", style: TextStyle(fontSize: 11, color: motorStatus ? Colors.white : AppColor.duBlue),)
                                  ],
                                ),

                              ),
                            ],
                          ),

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
                                  onPressed: _toggleRun,
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
                  padding: EdgeInsets.fromLTRB(0, 30, 0, 0),
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

              // 필터 정보 표시
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.01),
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    spacing: 5,
                    //
                    children: [
                      Text("필터 사용시간 : $filterTime", style: TextStyle(fontSize: 12),),

                      Text("필터 교체횟수 : $filterCount", style: TextStyle(fontSize:12),)
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