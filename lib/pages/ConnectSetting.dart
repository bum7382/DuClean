import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/services/routes.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/services/modbus_manager.dart';

class ConnectSettingPage extends StatelessWidget {
  const ConnectSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dev = context.watch<SelectedDevice>().current;

    final w = context.screenWidth;
    final h = context.screenHeight;

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

    // [핵심 조건] MAC 주소가 비어있지 않은지 확인
    final hasMacAddress = dev.macAddress.isNotEmpty;

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
        mainAxisAlignment: MainAxisAlignment.start,
        spacing: h * 0.03,
        children: [
          SizedBox(height: h * 0.02),
          // 로고 및 기기명
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

          // 정보 표시 컨테이너
          Container(
            width: w * 0.9,
            // 내용물에 따라 높이 유동적 (MAC 추가로 인해)
            constraints: BoxConstraints(minHeight: h * 0.2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EEF6), width: 1),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(w * 0.08),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoRow('연결 상태', isConnected ? '연결됨' : '연결 끊김',
                      isConnected ? Colors.black : Colors.red),
                  const SizedBox(height: 8),
                  _infoRow('IP', dev.address, Colors.black),
                  const SizedBox(height: 8),
                  _infoRow('Unit ID', '${dev.unitId}', Colors.black),
                  const SizedBox(height: 8),
                  // [추가] MAC 주소 표시
                  _infoRow(
                    '기기 와이파이',
                    hasMacAddress ? 'DUCLEAN_${dev.macAddress}' : '정보 없음',
                    hasMacAddress ? Colors.black : Colors.redAccent,
                    15,
                    14
                  ),
                ],
              ),
            ),
          ),

          // 연결 버튼
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
                  await ModbusManager.instance.ensureConnected(
                    context,
                    host: dev.address,
                    unitId: dev.unitId,
                    name: dev.name,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('연결 성공')));
                }
              } catch (e) {
                String error = "";
                if (e.toString().contains("not responding")) {
                  error = "기기가 응답하지 않습니다. 기기 전원과 와이파이를 확인해주세요.";
                } else if (e.toString().contains("timeout")) {
                  error = "응답 시간 초과. 네트워크 상태를 확인해주세요.";
                } else {
                  error = "연결 실패: $e";
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

          // 홈으로 가기 버튼 (조건: 연결됨 AND 맥주소 있음)
          if (isConnected && hasMacAddress)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColor.duBlue,
                elevation: 2,
                textStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 20),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 30, vertical: 10),
              ),
              onPressed: () {
                Navigator.of(context).pushNamed(Routes.mainPage);
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 10,
                children: [
                  Icon(Icons.home_outlined, color: Colors.white, size: 20),
                  Text("홈 화면으로", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                ],
              ),
            )
          else if (isConnected && !hasMacAddress)
          // [추가] 연결은 됐는데 MAC이 없어서 못 넘어가는 경우 안내
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                "MAC 주소가 없습니다.\n기기 목록에서 [수정]을 눌러 스캔을 다시 진행해주세요.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColor.duRed, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // 정보 표시용 위젯 추출
  Widget _infoRow(String label, String value, Color valueColor, [double size1 = 17, double size2 = 18]) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: size1,
            color: Color(0xff444444),
          ),
        ),
        const Spacer(),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: size2,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}