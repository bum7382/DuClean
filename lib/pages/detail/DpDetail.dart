import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:duclean/common/context_extensions.dart';

import 'package:duclean/providers/dp_history.dart';
import 'package:duclean/res/customWidget.dart';
import 'package:duclean/providers/selected_device.dart';

import 'package:duclean/res/settingWidget.dart';
import 'package:settings_ui/settings_ui.dart';

class DpDetailPage extends StatefulWidget {
  const DpDetailPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;

  @override
  State<DpDetailPage> createState() => _DpDetailPageState();
}

class _DpDetailPageState extends State<DpDetailPage> {
  int? _dpHighLimit;
  int? _dpHighAlarmDelay;
  int? _dpLowLimit;
  int? _dpLowAlarmDelay;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDpSettings();
  }

  Future<void> _loadDpSettings() async {
    // 네가 준 번지수 기준
    // 29 : 과차압 설정
    // 65 : 과차압 알람지연
    // 67 : 저차압 설정
    // 68 : 저차압 알람지연
    // 32 : 과전류 설정
    // 44 : 전류 편차 (여기서는 안 씀)

    final dHLimit  = await widget.readRegister(29) ?? 0;
    final dHAlarmD = await widget.readRegister(65) ?? 0;
    final dLLimit  = await widget.readRegister(67) ?? 0;
    final dLAlarmD = await widget.readRegister(68) ?? 0;

    if (!mounted) return;
    setState(() {
      _dpHighLimit      = dHLimit;
      _dpHighAlarmDelay = dHAlarmD;
      _dpLowLimit       = dLLimit;
      _dpLowAlarmDelay  = dLAlarmD;
      _loading          = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sel = context.watch<SelectedDevice>().current;
    if (sel == null) {
      return const Scaffold(
        body: Center(child: Text('선택된 기기가 없습니다.')),
      );
    }

    final host = sel.address;
    final unitId = sel.unitId;

    final dpHistory = context.watch<DpHistory>();
    final history = dpHistory.pointsFor(host, unitId);

    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          title: const Text(
            '차압 그래프',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          backgroundColor: AppColor.duBlue,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColor.duBlue),
        ),
      );
    }

    int dpHighLimit      = _dpHighLimit!;
    int dpHighAlarmDelay = _dpHighAlarmDelay!;
    int dpLowLimit       = _dpLowLimit!;
    int dpLowAlarmDelay  = _dpLowAlarmDelay!;

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        title: const Text(
          '차압 그래프',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppColor.duBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: history.isEmpty
            ? const Center(child: Text('수집된 차압 데이터가 없습니다.'))
            : SettingsList(
          lightTheme: const SettingsThemeData(
            settingsListBackground: AppColor.bg, // 원하는 색으로
          ),
          sections: [
            SettingsSection(
              margin: const EdgeInsetsDirectional.only(bottom: 16),
              tiles: [
                CustomSettingsTile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 현재 차압 표시 카드
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.01),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          spacing: w * 0.07,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 25, 0, 0),
                              child: SizedBox(
                                width: w * 0.3,
                                child: GaugeTile(
                                  title: '차압',
                                  valueStr: dpHistory
                                      .latestDpFor(host, unitId)
                                      .toInt()
                                      .toString(),
                                  unit: 'mmAq',
                                  max: 500,
                                  size: w * 0.3,
                                  color: AppColor.duBlue,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(0, h * 0.04, 0, 0),
                              child: Column(
                                spacing: 4,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "현재 차압: ",
                                    style: TextStyle(
                                      fontSize: w * 0.04,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    "${dpHistory.latestDpFor(host, unitId).toInt()}mmAq",
                                    style: TextStyle(
                                      fontSize: w * 0.06,
                                      fontWeight: FontWeight.w600,
                                      color: AppColor.duBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 차압 히스토리 라인 그래프
                      SizedBox(
                        height: h * 0.45,
                        child: _DpHistoryChart(
                          dpHighLimit: dpHighLimit,
                          dpLowLimit: dpLowLimit,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ───────── 하단: 과차압 / 저차압 설정 섹션 ─────────
            SettingsSection(
              margin: const EdgeInsetsDirectional.only(top: 4, bottom: 100),
              title: const Text("과차압"),
              tiles: [
                SettingsTile.navigation(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('과차압 설정값'),
                  value: Text('$dpHighLimit mmAq'),
                  onPressed: (_) async {
                    final saved = await showRegisterNumberEditor(
                      context: context,
                      title: '과차압 값 설정',
                      icon: Icons.timer_outlined,
                      address: 29,
                      initialValue: dpHighLimit,
                      writeRegister: widget.writeRegister,
                      min: 0,
                      max: 500,
                      accentColor: AppColor.duBlue,
                      hintText: '0 ~ 500',
                    );
                    if (saved != null && mounted) {
                      setState(() => _dpHighLimit = saved);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('과차압 값이 저장되었습니다.')),
                      );
                    }
                  },
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.timer),
                  title: const Text('과차압 알람지연'),
                  value: Text('$dpHighAlarmDelay 초'),
                  onPressed: (_) async {
                    final saved = await showRegisterNumberEditor(
                      context: context,
                      title: '과차압 알람지연 설정',
                      icon: Icons.timer,
                      address: 65,
                      initialValue: dpHighAlarmDelay,
                      writeRegister: widget.writeRegister,
                      min: 0,
                      max: 600,
                      accentColor: AppColor.duBlue,
                      hintText: '0 ~ 600',
                    );
                    if (saved != null && mounted) {
                      setState(() => _dpHighAlarmDelay = saved);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('과차압 알람지연이 저장되었습니다.')),
                      );
                    }
                  },
                ),
              ],
            ),
            SettingsSection(
              margin: const EdgeInsetsDirectional.only(top: 4, bottom: 100),
              title: const Text("저차압"),
              tiles: [
                SettingsTile.navigation(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('저차압 설정값'),
                  value: Text('$dpLowLimit mmAq'),
                  onPressed: (_) async {
                    final saved = await showRegisterNumberEditor(
                      context: context,
                      title: '저차압 값 설정',
                      icon: Icons.timer_outlined,
                      address: 67,
                      initialValue: dpLowLimit,
                      writeRegister: widget.writeRegister,
                      min: 0,
                      max: 500,
                      accentColor: AppColor.duBlue,
                      hintText: '0 ~ 500',
                    );
                    if (saved != null && mounted) {
                      setState(() => _dpLowLimit = saved);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('저차압 값이 저장되었습니다.')),
                      );
                    }
                  },
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.timer),
                  title: const Text('저차압 알람지연'),
                  value: Text('$dpLowAlarmDelay 초'),
                  onPressed: (_) async {
                    final saved = await showRegisterNumberEditor(
                      context: context,
                      title: '저차압 알람지연 설정',
                      icon: Icons.timer,
                      address: 68,
                      initialValue: dpLowAlarmDelay,
                      writeRegister: widget.writeRegister,
                      min: 0,
                      max: 600,
                      accentColor: AppColor.duBlue,
                      hintText: '0 ~ 600',
                    );
                    if (saved != null && mounted) {
                      setState(() => _dpLowAlarmDelay = saved);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('저차압 알람지연이 저장되었습니다.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );

  }
}

class _DpHistoryChart extends StatefulWidget {
  final int dpHighLimit, dpLowLimit;
  const _DpHistoryChart({
    super.key,
    required this.dpHighLimit,
    required this.dpLowLimit,
  });

  @override
  State<_DpHistoryChart> createState() => _DpHistoryChartState();
}

class _DpHistoryChartState extends State<_DpHistoryChart> {
  // 절대 Y 범위
  static const double ABSOLUTE_MIN_Y = 0;
  static const double ABSOLUTE_MAX_Y = 500;

  // X축: 최대 60분
  static const int TOTAL_CHART_MINUTES = 60;

  // 한 화면에 보여줄 분(뷰포트)
  static const double VIEW_WINDOW_MINUTES = 30;

  @override
  Widget build(BuildContext context) {
    final sel = context.watch<SelectedDevice>().current;

    if (sel == null) {
      return const Center(child: Text('선택된 기기가 없습니다.'));
    }

    final host = sel.address;
    final unitId = sel.unitId;

    final dpHistory = context.watch<DpHistory>();
    final history = dpHistory.pointsFor(host, unitId);

    if (history.isEmpty) {
      return const Center(child: Text('최근 1시간 데이터가 없습니다.'));
    }

    final now = DateTime.now();
    final from = now.subtract(const Duration(minutes: TOTAL_CHART_MINUTES));

    // 최근 1시간 데이터만 사용
    final recent = history.where((p) => !p.time.isBefore(from)).toList();
    if (recent.isEmpty) {
      return const Center(child: Text('최근 1시간 데이터가 없습니다.'));
    }

    final spots = <FlSpot>[];
    final values = <double>[];

    for (final p in recent) {
      final minutes = p.time.difference(from).inSeconds / 60.0;
      final clamped = p.value
          .clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y)
          .toDouble();
      spots.add(FlSpot(minutes, clamped));
      values.add(clamped);
    }

    // Y축 자동 범위 계산
    double dataMin = values.reduce((a, b) => a < b ? a : b);
    double dataMax = values.reduce((a, b) => a > b ? a : b);

    dataMin -= 10;
    dataMax += 10;

    double chartMinY =
    dataMin.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y).toDouble();
    double chartMaxY =
    dataMax.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y).toDouble();

    if (chartMaxY - chartMinY < 20) {
      chartMaxY =
          (chartMinY + 20).clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);
    }

    chartMinY = (chartMinY - 1).clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);
    chartMaxY = (chartMaxY + 1).clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);

    const double yInterval = 10.0;

    final double highLimitY = widget.dpHighLimit
        .toDouble()
        .clamp(chartMinY, chartMaxY);
    final double lowLimitY = widget.dpLowLimit
        .toDouble()
        .clamp(chartMinY, chartMaxY);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면 너비
        final viewWidth = constraints.maxWidth;
        // 60분 / 30분 = 2배 폭
        final chartWidth = viewWidth * (TOTAL_CHART_MINUTES / VIEW_WINDOW_MINUTES);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: TOTAL_CHART_MINUTES.toDouble(), // 여전히 0~60분
                minY: chartMinY,
                maxY: chartMaxY,
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((barSpot) {
                        final x = barSpot.x;
                        final dt = from.add(Duration(seconds: (x * 60).round()));
                        final hh = dt.hour.toString().padLeft(2, '0');
                        final mm = dt.minute.toString().padLeft(2, '0');
                        final value = barSpot.y.toInt();

                        return LineTooltipItem(
                          '$hh:$mm\n',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          children: [
                            TextSpan(
                              text: '$value mmAq',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return const FlLine(
                      color: Color(0xff37434d),
                      strokeWidth: 0.2,
                    );
                  },
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: const Color(0xff37434d), width: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() % 10 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.toInt().toString(),
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                      reservedSize: 32,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        // 범위 밖이면 표시 안 함
                        if (value < 0 || value > TOTAL_CHART_MINUTES) {
                          return const SizedBox.shrink();
                        }

                        // 🔹 오른쪽 끝 레이블은 잘리니까 표시 안 함
                        if ((TOTAL_CHART_MINUTES - value).abs() < 0.1) {
                          // value == TOTAL_CHART_MINUTES 인 경우
                          return const SizedBox.shrink();
                        }

                        final dt = from.add(
                          Duration(seconds: (value * 60).round()),
                        );
                        final hh = dt.hour.toString().padLeft(2, '0');
                        final mm = dt.minute.toString().padLeft(2, '0');
                        final label = '$hh:$mm';

                        return SideTitleWidget(
                          meta: meta,
                          space: 4,
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                      reservedSize: 24,
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (widget.dpHighLimit > 0)
                      HorizontalLine(
                        y: highLimitY,
                        color: AppColor.duRed,
                        strokeWidth: 1.5,
                        dashArray: const [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          labelResolver: (_) =>
                          '과차압 ${widget.dpHighLimit} mmAq',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColor.duRed,
                          ),
                        ),
                      ),
                    if (widget.dpLowLimit > 0)
                      HorizontalLine(
                        y: lowLimitY,
                        color: AppColor.duGreen,
                        strokeWidth: 1.5,
                        dashArray: const [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topLeft,
                          labelResolver: (_) =>
                          '저차압 ${widget.dpLowLimit} mmAq',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColor.duGreen,
                          ),
                        ),
                      ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    gradient: LinearGradient(
                      colors: [
                        AppColor.duBlue,
                        AppColor.duBlue.withAlpha(450),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColor.duBlue.withAlpha(3),
                          AppColor.duBlue.withAlpha(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
