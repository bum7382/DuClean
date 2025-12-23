import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duclean/services/auth_service.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';

class PasswordInputPage extends StatefulWidget {
  final String? targetRoute;

  const PasswordInputPage({super.key, this.targetRoute});

  @override
  State<PasswordInputPage> createState() => _PasswordInputPageState();
}

class _PasswordInputPageState extends State<PasswordInputPage> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleVerify() async {
    final authService = context.read<AuthService>();
    final selectedDevice = context.read<SelectedDevice>().current;

    if (selectedDevice == null) {
      setState(() => _errorMessage = "선택된 장치가 없습니다.");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 장비의 암호와 비교
    bool isOk = await authService.checkDevicePassword(
      context,
      host: selectedDevice.address,
      unitId: selectedDevice.unitId,
      name: selectedDevice.name,
      input: _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (isOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("인증에 성공하였습니다.")),
        );
      } else {
        setState(() => _errorMessage = "암호가 일치하지 않거나 장치 응답이 없습니다.");
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    final h = context.screenHeight;
    final portrait = context.isPortrait;

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        title: const Text("관리자 인증"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: AppColor.duBlue),
            const SizedBox(height: 24),
            const Text(
              "메뉴 접근을 위해 관리자 인증이 필요합니다.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _passwordController,
              keyboardType: TextInputType.number,
              obscureText: true, // 암호화 표시
              decoration: InputDecoration(
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2.0),
                ),
                labelText: "비밀번호 입력",
                labelStyle: TextStyle(color: AppColor.duBlack),
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
                prefixIcon: const Icon(Icons.key),
              ),
              onSubmitted: (_) => _handleVerify(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: h * 0.06,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.duBlue,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("인증", style: TextStyle(fontSize: 16)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: AppColor.duRed),),
            ),
          ],
        ),
      ),
    );
  }
}