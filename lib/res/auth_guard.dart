import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duclean/services/auth_service.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/services/routes.dart';

class AuthGuard extends StatelessWidget {
  final Widget child;
  final String title;
  final bool isTab; // 탭 메뉴인지 여부 확인용

  const AuthGuard({
    super.key,
    required this.child,
    this.title = "관리자 인증",
    this.isTab = false, // 기본값은 일반 페이지(false)
  });

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<SelectedDevice>().current;
    final auth = context.watch<AuthService>();

    bool hasAdminAccess = false;
    if (selected != null) {
      hasAdminAccess = auth.isAdminMode(selected.address, selected.unitId);
    }

    if (hasAdminAccess) {
      return child;
    }

    // 1. 권한이 없을 때 보여줄 공통 UI (알맹이)
    Widget lockedContent = Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColor.bg,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_person_outlined, size: 80, color: AppColor.duLightGrey),
          const SizedBox(height: 24),
          const Text(
            "관리자 전용 메뉴",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            "이 메뉴를 사용하려면\n'연결 설정'에서 관리자 인증이 필요합니다.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColor.duGrey, height: 1.5),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pushNamed(Routes.connectSettingPage);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.duBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("인증하러 가기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );

    // 2. 상황에 따라 Scaffold로 감쌀지 결정
    if (isTab) {
      // 하단바 메뉴일 경우: 기존 AppBar를 쓰므로 알맹이만 반환
      return lockedContent;
    } else {
      // 일반 페이지로 이동했을 경우: 뒤로가기 버튼이 포함된 Scaffold 반환
      return Scaffold(
        appBar: AppBar(
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
          backgroundColor: AppColor.duBlue,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: lockedContent,
      );
    }
  }
}