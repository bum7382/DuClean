import 'package:duclean/Alarm.dart';
import 'package:duclean/Main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class Routes {
  Routes._();

  static const String mainPage = '/mainPage';
  static const String alarmPage = '/alarmPage';

  static final routes = <String, WidgetBuilder>{
    mainPage: (BuildContext context) => MainPage(),
    alarmPage: (BuildContext context) => AlarmPage(),
  };
}