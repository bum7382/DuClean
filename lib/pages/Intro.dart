import 'package:duclean/pages/Main.dart';
import 'package:duclean/res/customWidget.dart';
import 'package:duclean/services/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:duclean/res/Constants.dart';
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/providers/dp_history.dart';
import 'package:duclean/providers/power_history.dart';
import 'package:duclean/common/context_extensions.dart';
import 'dart:math';



void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SelectedDevice()),
        ChangeNotifierProvider(create: (_) => ConnectionRegistry()),
        ChangeNotifierProvider(create: (_) => DpHistory()),
        ChangeNotifierProvider(create: (_) => PowerHistory()),
      ],
      child: const MyApp(),
    ),
  );
}

// 앱
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 기본 설정, 테마, 메인화면
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DuClean',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        textSelectionTheme: const TextSelectionThemeData(
          selectionHandleColor: AppColor.duBlue,
        ),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return Colors.grey.shade300;
            }
            return null;
          }),

          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return Colors.grey.shade500;
            }
            return null;
          }),
        ),
      ),
      onGenerateRoute: Routes.onGenerateRoute,
      home: const IntroPage(),
    );
  }
}

// 메인 화면
class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {

    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    // 세로 모드 여부
    final portrait = context.isPortrait;


    return Scaffold(
        backgroundColor: AppColor.bg,
        // 상단 바
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_white.png', width: 100),
              Padding(
                padding: const EdgeInsets.only(top:6),
                child: Text(AppConst.version, style: TextStyle(color: Colors.white, fontSize: 13),),
              )
            ],
          ),
          backgroundColor: AppColor.duBlue,
        ),
        // 몸체
        body: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: Center(
              child: Column(
                spacing: 100,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: 100,),
                  Text("Your Standard,\nDUCLEAN",style:
                  TextStyle(fontSize: w * 0.08, fontWeight: FontWeight.w700,color: AppColor.duBlue),
                    textAlign: TextAlign.center,),
                  // 연결 목록 버튼
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pushNamed(Routes.connectListPage);
                    },
                    child: BlueContainer(
                      width: w * 0.6,
                      height: portrait ? h * 0.07 : h * 0.2,
                      radius: 100,
                      child: Center(
                        child: Text('연결 목록', style: TextStyle(color: Colors.white, fontSize: w * 0.05, fontWeight: FontWeight.w600),)
                      ),
                    ),
                  ),

                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 10,
          color: AppColor.duBlue,
        )
    );
  }
}