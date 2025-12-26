import 'package:duclean/res/customWidget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/services/routes.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/services/modbus_manager.dart';
import 'package:duclean/services/auth_service.dart';

class ConnectSettingPage extends StatelessWidget {
  const ConnectSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dev = context.watch<SelectedDevice>().current;

    final w = context.screenWidth;
    final h = context.screenHeight;

    final auth = context.watch<AuthService>();

    if (dev == null) {
      return Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          centerTitle: false,
          title: const Text('기기 연결/권한 설정',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).popUntil((route) => route.settings.name == Routes.connectListPage),
          ),
          backgroundColor: AppColor.duBlue,
        ),
        body: const Center(child: Text('선택된 기기가 없습니다.')),
      );
    }

    final isConnected = context.select<ConnectionRegistry, bool>(
          (r) => r.stateOf(dev.address, dev.unitId).connected,
    );

    final hasMacAddress = dev.macAddress.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColor.bg,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        centerTitle: false,
        title: const Text('기기 연결/권한 설정',
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
                  /*
                  _infoRow(
                    'IoT기기[MAC]',
                    hasMacAddress ? '${dev.macAddress}' : '정보 없음',
                    hasMacAddress ? Colors.black : Colors.redAccent,
                    15,
                    14
                  ),
                  */
                ],
              ),
            ),
          ),
          // 권한 설정 섹션 추가
          // 아이콘 + title 25.12.24
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              const Icon(Icons.lock_person, size: 35.0, color: Colors.red),
              Text(
                '집진기 조작 권한 설정',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: w * 0.05,
                  color: AppColor.duBlack,
                ),
              ),
            ],
          ),

          _buildPermissionSection(context, auth, dev),

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
                Navigator.of(context).pushReplacementNamed(Routes.mainPage);
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

// --- 권한 설정 위젯 빌더 ---
Widget _buildPermissionSection(BuildContext context, AuthService auth, dynamic dev) {
  final isUser = auth.isUserMode(dev.address, dev.unitId);
  final isAdmin = auth.isAdminMode(dev.address, dev.unitId);

  return BgContainer(
    width: MediaQuery.of(context).size.width * 0.9,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
    child: Column(
      children: [
        // 사용자 권한 토글
        SwitchListTile(
          title: const Text("사용자", style: TextStyle(fontWeight: FontWeight.bold)),
          value: isUser,
          activeThumbColor: AppColor.duBlue,
          onChanged: (val) => _handlePermissionToggle(context, "사용자", val, "1111", dev.address, dev.unitId),
        ),
        // 관리자 권한 토글
        if (isUser) ...[
          const Divider(),
          SwitchListTile(
            title: Text("관리자", style: TextStyle(fontWeight: FontWeight.bold)),
            value: isAdmin,
            activeThumbColor: AppColor.duBlue,
            onChanged: (val) => _handlePermissionToggle(context, "관리자", val, "1661", dev.address, dev.unitId),
          ),
        ]
      ],
    ),
  );
}

// --- 비밀번호 확인 및 토글 로직 ---
void _handlePermissionToggle(BuildContext context, String type, bool value, String correctPw, String host, int unitId) {
  final auth = context.read<AuthService>();

  if (!value) {
    if (type == "사용자") auth.setUserMode(host, unitId, false);
    if (type == "관리자") auth.setAdminMode(host, unitId, false);
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) {
      String input = "";
      String? errorText; // 에러 메시지 상태 관리 변수

      return StatefulBuilder( // 다이얼로그 내부 상태 변경을 위해 필요
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColor.bg,
            title: Text("$type 권한 인증"),
            content: TextField(
              autofocus: true,
              obscureText: true,
              cursorColor: AppColor.duBlue,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColor.duBlue),
              decoration: InputDecoration(
                hintText: "비밀번호 4자리를 입력하세요",
                hintStyle: const TextStyle(color: Colors.grey),

                // --- 에러 처리 핵심 부분 ---
                errorText: errorText,
                errorStyle: const TextStyle(color: Colors.red),

                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2),
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 1),
                ),
                errorBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.red, width: 1),
                ),
                focusedErrorBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.red, width: 2),
                ),
                // --------------------------
              ),
              onChanged: (v) {
                input = v;
                // 다시 입력하기 시작하면 에러 메시지 삭제
                if (errorText != null) {
                  setState(() => errorText = null);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("취소", style: TextStyle(color: AppColor.duRed)),
              ),
              TextButton(
                onPressed: () {
                  if (input == correctPw) {
                    if (type == "사용자") auth.setUserMode(host, unitId, true);
                    if (type == "관리자") auth.setAdminMode(host, unitId, true);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("인증 성공"),
                        backgroundColor: AppColor.duBlue,
                      ),
                    );
                  } else {
                    // 에러 상태 업데이트 (TextField 하단에 메시지 노출)
                    setState(() {
                      errorText = "비밀번호가 틀렸습니다";
                    });
                  }
                },
                child: const Text("확인", style: TextStyle(color: AppColor.duBlue)),
              ),
            ],
          );
        },
      );
    },
  );
}