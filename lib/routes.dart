import 'package:duclean/Alarm.dart';
import 'package:duclean/Main.dart';
import 'package:duclean/ConnectList.dart';
import 'package:duclean/ConnectSetting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class Routes {
  Routes._();

  static const String mainPage = '/mainPage';
  static const String alarmPage = '/alarmPage';
  static const String connectListPage = '/connectListPage';
  static const String connectSettingPage = '/connectSettingPage';

  static final routes = <String, WidgetBuilder>{
    connectListPage: (BuildContext context) => ConnectListPage(),
    connectSettingPage: (BuildContext context) => ConnectSettingPage(),
    mainPage: (BuildContext context) => MainPage(),
    alarmPage: (BuildContext context) => AlarmPage(),
  };
}