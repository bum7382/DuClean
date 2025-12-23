import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duclean/services/auth_service.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/services/routes.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // 1. 현재 선택된 기기 정보를 가져옵니다.
    final selected = context.watch<SelectedDevice>().current;

    // 2. AuthService를 가져옵니다.
    final auth = context.watch<AuthService>();

    // 3. 현재 기기가 있고, 그 기기의 관리자 권한이 켜져 있는지 확인합니다.
    bool hasAdminAccess = false;
    if (selected != null) {
      hasAdminAccess = auth.isAdminMode(selected.address, selected.unitId);
    }

    if (hasAdminAccess) {
      return child; // 관리자 권한이 있으면 페이지 노출
    } else {
      // 권한이 없으면 안내 화면 노출
      return Scaffold(
        backgroundColor: AppColor.bg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: AppColor.duLightGrey),
              const SizedBox(height: 20),
              const Text(
                "관리자 전용 메뉴입니다.",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "연결 설정 탭에서 '관리자 권한'을\n인증 후 활성화해 주세요.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColor.duGrey),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  // 설정 탭으로 이동 (Navigator 구조에 따라 조절 필요)
                  Navigator.of(context).pushNamed(Routes.connectSettingPage);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.duBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                ),
                child: const Text("확인", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        ),
      );
    }
  }
}