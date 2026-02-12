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
import 'package:duclean/services/motor_schedule_service.dart';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:duclean/services/auth_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async{
  WidgetsFlutterBinding.ensureInitialized();

  // 모터 스케줄 서비스 초기화 (저장된 스케줄 복구 + 타이머 재설정)
  MotorScheduleService().init(appNavigatorKey);
  await dotenv.load(fileName: ".env");
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
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
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'), // 한국어 추가
      ],
      locale: const Locale('ko', 'KR'),
      title: 'DuClean',
      theme: ThemeData(
        fontFamily: 'Pretendard',
        textSelectionTheme: const TextSelectionThemeData(
          selectionHandleColor: AppColor.duBlue,
        ),
        switchTheme: SwitchThemeData(
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return Colors.white10;
            }
            return null;
          }),

          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return AppColor.duLightGrey;
            }
            return null;
          }),
          trackOutlineColor: WidgetStateProperty.resolveWith((states) {
            if (!states.contains(WidgetState.selected)) {
              return AppColor.duLightGrey;
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
                  //앱사용 환경 안내 25.12.11
                  SizedBox(height: 20,),
                  Text("이 앱은 AirPulse형 집진기 전용입니다. \n IoT 컨트롤러에 RS485통신이 연결된 상태에서 사용가능합니다.\n\n-사용가능 집진기 모델 :AP, APD, APH, APR, FC, HD ",style:
                  TextStyle(fontSize: w * 0.02, fontWeight: FontWeight.w200,color: AppColor.duBlue),
                    textAlign: TextAlign.center,),
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