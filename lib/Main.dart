import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'dart:async';

import 'package:syncfusion_flutter_gauges/gauges.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  String log0 = "읽는 중...";
  String log1 = "읽는 중...";
  String log2 = "읽는 중...";
  @override
  void initState() {
    super.initState();
    // 1초마다 읽기
    Timer.periodic(const Duration(seconds: 1), (_) async {
      final results = await Future.wait([
        readRegister(0),
        readRegister(1),
        readRegister(2),
      ]);

      final v0 = results[0];
      final v1 = results[1];
      final v2 = results[2];

      if (mounted) {
        setState(() {
          log0 = '${v0?.toInt() ?? 0}';
          log1 = '${((v1?.toDouble() ?? 0) / 10).toStringAsFixed(1)}';
          log2 = '${((v2?.toDouble() ?? 0) / 10).toStringAsFixed(1)}';
        });
      }
    });
  }
  // Modbus 읽기 함수
  Future<num?> readRegister(int address) async {
    try {
      // Modbus 클라이언트 생성
      final client = ModbusClientTcp("192.168.10.190", unitId: 1);
      await client.connect();

      // 연결할 주소 정보
      final register = ModbusInt16Register(
        name: "Register",
        type: ModbusElementType.inputRegister,
        address: address,
      );

      await client.send(register.getReadRequest()); // 읽기 요청
      await client.disconnect();
      return register.value;
    } catch (e) {
      debugPrint("Modbus 읽기 에러: $e");
    }
  }

  /// Modbus 쓰기 함수
  Future<void> writeRegister(int address, int value) async {
    try {
      // Modbus 클라이언트 생성
      final client = ModbusClientTcp("192.168.10.190", unitId: 1);
      await client.connect();

      // 연결할 주소 정보
      final register = ModbusInt16Register(
        name: "Register",
        type: ModbusElementType.holdingRegister,
        address: address,
      );

      // 값 쓰기 요청
      await client.send(register.getWriteRequest(value));

      await client.disconnect();
    } catch (e) {
      debugPrint("Modbus 쓰기 에러: $e");
    }
  }



  @override
  Widget build(BuildContext context) {
    // 버전
    var version = 'V 1.0.0';
    // 공식 색
    const Color duBlue = Color(0xff004d94);

    return Scaffold(
      backgroundColor: const Color(0xfff6f6f6),
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo_white.png', width: 100),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                version,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            )
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: duBlue,
      ),
      body: Center(
        child: ListView(
          children: [
            Text('차압', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700,)),
            SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  startAngle: 180,
                  endAngle: 0,
                  minimum: 0,
                  maximum: 500,
                  axisLineStyle: AxisLineStyle(
                    thickness: 50,
                  ),
                  pointers: <GaugePointer>[
                    RangePointer(
                      value: double.tryParse(log0) ?? 0,
                      color: duBlue,
                      width: 50,
                    ),
                    MarkerPointer(
                      value: double.tryParse(log0) ?? 0,
                      color: Colors.white,
                      borderWidth: 1,
                      borderColor: Colors.black,
                      markerType: MarkerType.triangle,
                      markerWidth: 15,
                      markerHeight: 70,
                    )
                  ],
                  annotations: <GaugeAnnotation>[
                    GaugeAnnotation(
                      angle: -90,
                      positionFactor: 0.1,
                      widget:

                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(log0, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30)),
                            Text('mmAq', style: TextStyle(fontSize: 12)),
                          ],
                        )
                    )
                  ]
                )
              ],
            ),
            Text('전류1', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, )),
            SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                    startAngle: 180,
                    endAngle: 0,
                    minimum: 0,
                    maximum: 500,
                    axisLineStyle: AxisLineStyle(
                      thickness: 50,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: double.tryParse(log1) ?? 0,
                        color: duBlue,
                        width: 50,
                      ),
                      MarkerPointer(
                        value: double.tryParse(log1) ?? 0,
                        color: Colors.white,
                        borderWidth: 1,
                        borderColor: Colors.black,
                        markerType: MarkerType.triangle,
                        markerWidth: 15,
                        markerHeight: 70,
                      )
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                          angle: -90,
                          positionFactor: 0.1,
                          widget:

                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(log1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30)),
                              Text('A', style: TextStyle(fontSize: 12)),
                            ],
                          )
                      )
                    ]
                )
              ],
            ),
            Text('전류2', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, )),
            SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                    startAngle: 180,
                    endAngle: 0,
                    minimum: 0,
                    maximum: 500,
                    axisLineStyle: AxisLineStyle(
                      thickness: 50,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: double.tryParse(log2) ?? 0,
                        color: duBlue,
                        width: 50,
                      ),
                      MarkerPointer(
                        value: double.tryParse(log2) ?? 0,
                        color: Colors.white,
                        borderWidth: 1,
                        borderColor: Colors.black,
                        markerType: MarkerType.triangle,
                        markerWidth: 15,
                        markerHeight: 70,
                      )
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                          angle: -90,
                          positionFactor: 0.1,
                          widget:

                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(log2, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30)),
                              Text('A', style: TextStyle(fontSize: 12)),
                            ],
                          )
                      )
                    ]
                )
              ],
            ),
            Row(
              spacing: 20,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: ElevatedButton(
                    onPressed: () async {
                      await writeRegister(0, 1);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(10),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Color(0xff2bc735), width:3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      shadowColor: Color(0xff2bc735),
                      elevation: 2,
                      textStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 25)


                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("I", style:TextStyle(color: Color(0xff2bc735))),
                        Text("운전", style:TextStyle(color: Color(0xff2bc735))),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 150,
                  height: 150,
                  child: ElevatedButton(
                    onPressed: () async {
                      await writeRegister(0, 0);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF3E3D),
                      padding: const EdgeInsets.all(10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      shadowColor: Color(0xFFFF3E3D),
                      elevation: 2,
                      textStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 25)
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Ο", style:TextStyle(color: Colors.white)),
                        Text("정지", style:TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
