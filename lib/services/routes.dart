import 'package:duclean/pages/Alarm.dart';
import 'package:duclean/pages/Main.dart';
import 'package:duclean/pages/ConnectList.dart';
import 'package:duclean/pages/ConnectSetting.dart';
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