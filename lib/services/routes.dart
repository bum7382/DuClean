import 'package:duclean/pages/Alarm.dart';
import 'package:duclean/pages/Main.dart';
import 'package:duclean/pages/ConnectList.dart';
import 'package:duclean/pages/ConnectSetting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:animations/animations.dart';

Route<T> buildFadeThroughRoute<T>({
  required Widget page,
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return page;
    },
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
  );
}



class Routes {
  Routes._();

  static const String mainPage = '/mainPage';
  static const String alarmPage = '/alarmPage';
  static const String connectListPage = '/connectListPage';
  static const String connectSettingPage = '/connectSettingPage';
  static const String motorCommandPage = '/motor-command';


  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case connectListPage:
        return buildFadeThroughRoute(
          page: const ConnectListPage(),
          settings: settings,
        );
      case connectSettingPage:
        return buildFadeThroughRoute(
          page: const ConnectSettingPage(),
          settings: settings,
        );
      case mainPage:
        return buildFadeThroughRoute(
          page: const MainPage(),
          settings: settings,
        );
      case alarmPage:
        return buildFadeThroughRoute(
          page: const AlarmPage(),
          settings: settings,
        );
      default:
        return null;
    }
  }
}
