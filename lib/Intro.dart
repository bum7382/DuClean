import 'package:duclean/Main.dart';
import 'package:duclean/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'dart:math';

/*
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 가로모드만 허용
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const MyApp());
}*/

void main() {
  runApp(const MyApp());
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
      theme: ThemeData(fontFamily: 'Pretendard'),
      routes: Routes.routes,
      home: const IntroPage(),
    );
  }
}

// 메인 화면
class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  // 페이지 이동 함수 - 현재 사용 안 함
  /*
  void navigateToPage(BuildContext context, String pageLabel) {
    Widget page;  // 이동할 페이지

    switch (pageLabel) {
      case 'FAN TEST':
        //page = const FanTestPage();
        page = const MainPage();
        break;
      case 'SOL TEST':
        //page = const SolTestPage();
        page = const MainPage();
        break;
      case 'SETTING':
        page = const MainPage();
        break;
      case 'STATE':
        //page = const StatePage();
        page = const MainPage();
        break;
      case 'INFO':
        page = const MainPage();
        //page = const InfoPage();
        break;
      default:
        page = Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: const Center(child: Text('Page not found!')),
        );
        break;
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }
  */

  @override
  Widget build(BuildContext context) {

    // 버전
    var version = 'V 1.0.1';
    // 공식 색
    var duBlue = Color(0xff004d94);

    // 화면 크기
    Size screenSize = MediaQuery.of(context).size;
    var screenWidth = screenSize.width;
    var screenHeight = screenSize.height;

    // 버튼 크기
    final double buttonWidth = screenWidth * 0.6;
    final double buttonHeight = screenHeight * 0.07;

    return Scaffold(
        backgroundColor: Color(0xfff6f6f6),
        // 상단 바
        appBar: AppBar(
          centerTitle: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_white.png', width: 100),
              Padding(
                padding: const EdgeInsets.only(top:6),
                child: Text(version, style: TextStyle(color: Colors.white, fontSize: 13),),
              )
            ],
          ),
          backgroundColor: duBlue,
        ),
        // 몸체
        body: Align(
          alignment: Alignment.topCenter,
          child: Center(
            child: Column(
              spacing: 100,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(height: 100,),
                Text("Your Standard,\nDUCLEAN",style:
                  TextStyle(fontSize: 30, fontWeight: FontWeight.w700,color: duBlue),
                            textAlign: TextAlign.center,),
                // 연결 목록 버튼
                SizedBox(
                  width: buttonWidth,
                  height: buttonHeight,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed(Routes.mainPage);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: duBlue,
                      foregroundColor: Colors.white,
                      textStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text('연결 목록'),
                  ),
                ),

              ],
            ),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          height: 10,
          color: duBlue,
        )
    );
  }
}
