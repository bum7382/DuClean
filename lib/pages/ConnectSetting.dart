import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart'; // SelectedDevice & ConnectionRegistry 포함
import 'package:duclean/services/routes.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/services/modbus_manager.dart';

class ConnectSettingPage extends StatelessWidget {
  const ConnectSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dev = context.watch<SelectedDevice>().current; // 전역 선택값

    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    // 세로 모드 여부(필요시 사용)
    final portrait = context.isPortrait;

    if (dev == null) {
      return Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          centerTitle: false,
          title: const Text('연결 설정',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          backgroundColor: AppColor.duBlue,
        ),
        body: const Center(child: Text('선택된 기기가 없습니다.')),
      );
    }

    final isConnected = context.select<ConnectionRegistry, bool>(
          (r) => r.stateOf(dev.address, dev.unitId).connected,
    );

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        centerTitle: false,
        title: const Text('연결 설정',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppColor.duBlue,
      ),
      body: Column(
        //child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        //crossAxisAlignment: CrossAxisAlignment.start,
          spacing: h * 0.03,
          children: [
            SizedBox(height: h * 0.02),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                Image.asset(
                  isConnected
                      ? "assets/images/logo_color.png"
                      : "assets/images/logo_black.png",
                  width: w * 0.1,
                ),
                Text(
                  dev.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: w * 0.05,
                    color: AppColor.duBlue,
                  ),
                ),
              ],
            ),
            Container(
              width: w * 0.9,
              height: h * 0.2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE8EEF6), width: 1), // 아주 연한 테두리
                boxShadow: const [
                  BoxShadow( // 바깥쪽 부드러운 그림자
                    color: Color(0x14000000), // 8% 검정
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                  BoxShadow( // 가까운 진한 그림자
                    color: Color(0x1A000000), // 10% 검정
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(w * 0.08),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch, // Row가 가로폭 꽉 채우도록
                  children: [
                    Row(
                      children: [
                        const Text('연결 상태',
                            style: TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 17, color: Color(0xff444444))),
                        const Spacer(),
                        Text(
                          isConnected ? '연결됨' : '연결 끊김',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 18, color: Colors.black),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('IP',
                            style: TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 17, color: Color(0xff444444))),
                        const Spacer(),
                        Text(
                          dev.address,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 18, color: Colors.black),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Unit ID',
                            style: TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 17, color: Color(0xff444444))),
                        const Spacer(),
                        Text(
                          '${dev.unitId}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 18, color: Colors.black),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? AppColor.duRed : AppColor.duBlue,
                elevation: 2,
                textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 20),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 30, vertical: 10),
              ),
              onPressed: () async {
                if (!context.mounted) return;
                try {
                  if (isConnected) {
                    await ModbusManager.instance.disconnect(
                      context,
                      host: dev.address,
                      unitId: dev.unitId,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('연결 해제됨')));
                  } else {
                    // 🔗 연결 (+ 슬레이브 응답 헬스체크 포함)
                    await ModbusManager.instance.ensureConnected(
                      context,
                      host: dev.address,
                      unitId: dev.unitId,
                      name: dev.name,

                      // verifyAddress: 1, // 필요시 명시적으로 핑 주소 지정 가능
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('연결 성공')));
                  }
                  // Registry가 갱신되며 isConnected는 자동으로 반영됨.
                } catch (e) {
                  String error = "";
                  if(e.toString().contains("not responding")){
                    error = "기기가 응답하지 않아 연결에 실패했습니다. 기기나 와이파이를 점검해주세요.";
                  }
                  else if(e.toString().contains("timeout")){
                    error = "기기가 정상적으로 응답하지 않아 연결에 실패했습니다. 연결 설정이 올바른지 점검해주세요.";
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Icon(isConnected ? Icons.link_off : Icons.link, color: Colors.white, size: 20),
                  Text(
                    isConnected ? "연결 끊기" : "연결",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),

                ],
              ),
            ),
            if(isConnected)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.duBlue,
                  elevation: 2,
                  textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 20),
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 30, vertical: 10),
                ),
                onPressed: (){Navigator.of(context).pushNamed(Routes.mainPage);},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 10,
                  children: [
                    Icon(Icons.home_outlined, color: Colors.white, size: 20),
                    Text("홈 화면으로", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),

                  ],
                ),
              )
          ],
        ),
    //  ),
    );
  }
}
