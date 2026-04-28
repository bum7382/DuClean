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
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]).then((_) {
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
  });
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
    // 세로 모드 여부 (현재 SystemChrome으로 portrait 고정이지만 분기 유지)
    final portrait = context.isPortrait;

    return Scaffold(
        backgroundColor: AppColor.bg,
        // 상단 바
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_white.png', width: context.s(100)),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  AppConst.version,
                  style: AppText.small(context).copyWith(color: Colors.white),
                ),
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
                spacing: context.s(100),
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: context.s(100)),
                  Text(
                    "Your Standard,\nDUCLEAN",
                    style: AppText.display(context).copyWith(color: AppColor.duBlue),
                    textAlign: TextAlign.center,
                  ),
                  // 연결 목록 버튼
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pushNamed(Routes.connectListPage);
                    },
                    child: BlueContainer(
                      width: context.wp(0.6),
                      height: portrait ? context.hp(0.07) : context.hp(0.2),
                      radius: AppRadius.pill,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '연결 목록',
                            style: AppText.title(context).copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  //앱사용 환경 안내 25.12.11
                  SizedBox(height: AppSpacing.lg),
                  Text(
                    "이 앱은 AirPulse형 집진기 전용입니다. \n IoT 컨트롤러에 RS485통신이 연결된 상태에서 사용가능합니다.\n\n-사용가능 집진기 모델 :AP, APD, APH, APR, FC, HD ",
                    style: AppText.caption(context).copyWith(
                      fontWeight: FontWeight.w200,
                      color: AppColor.duBlue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: context.s(10),
          color: AppColor.duBlue,
        )
    );
  }
}