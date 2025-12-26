import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:duclean/common/context_extensions.dart';

import 'package:duclean/providers/power_history.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/res/customWidget.dart';//추가 25.12.11
import 'package:settings_ui/settings_ui.dart';
import 'package:duclean/res/settingWidget.dart';
import 'package:duclean/services/auth_service.dart';
import 'package:duclean/services/routes.dart';

class PowerDetailPage extends StatefulWidget {
  const PowerDetailPage({
    super.key,
    required this.readRegister,
    required this.writeRegister,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;

  @override
  State<PowerDetailPage> createState() => _PowerDetailPageState();
}

class _PowerDetailPageState extends State<PowerDetailPage> {
  int? _powerLimit;
  int? _powerDelay;//추가
  int? _powerDiff;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPowerSettings();
  }

  Future<void> _loadPowerSettings() async {
    // 32 : 과전류 설정
    // 41 : 과전류 알람지연(EOCR 지연) 25.12.11
    // 44 : 전류 편차

    final pLimit = await widget.readRegister(32) ?? 0;
    final pDelay = await widget.readRegister(41) ?? 0;//과전류 알람지연 추가
    final pDiff  = await widget.readRegister(44) ?? 0;

    if (!mounted) return;
    setState(() {
      _powerLimit = pLimit;
      _powerDelay = pDelay;//추가
      _powerDiff  = pDiff;
      _loading    = false;
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

    // 권한 설정
    // 1. 현재 선택된 기기 정보 가져오기
    final selected = context.watch<SelectedDevice>().current;

    // 2. AuthService 가져오기
    final auth = context.watch<AuthService>();

    // 3. 현재 기기가 있고, 그 기기에 사용자 권한이 부여되었는지 확인
    bool hasAdminAccess = false;
    if (selected != null) {
      hasAdminAccess = auth.isAdminMode(selected.address, selected.unitId);
    }

    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    // 세로 모드 여부
    final portrait = context.isPortrait;


    if (_loading) {
      return Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          title: const Text(
            '전류 트렌드(설정)',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
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

    final powerLimit = _powerLimit!;
    final powerDelay = _powerDelay!;//추가
    final powerDiff  = _powerDiff!;

    final powerLimitA = powerLimit / 10.0; //전류 표시용-실수
    final powerDiffA = powerDiff / 10.0; //전류편차 표시용-실수

    final powerHistory = context.watch<PowerHistory>();
    final currentP1 = powerHistory.latestPowerFor(host, unitId, 1);//CT1
    final currentP2 = powerHistory.latestPowerFor(host, unitId, 2);//CT2


    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        title: const Text(
          '전류 트렌드(설정)',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppColor.duBlue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SettingsList(
          lightTheme: const SettingsThemeData(
            settingsListBackground: AppColor.bg,
          ),
          sections: [
            // ───────── 상단: 전류 게이지 + 그래프 ─────────
            SettingsSection(
              tiles: [
                CustomSettingsTile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // 현재 전류 표시 ( 2개)25.12.11
                    children: [
                    Text(
                      "[전류1] ${currentP1}A    [전류2] ${currentP2}A",
                      style: TextStyle(
                        fontSize: w * 0.03,
                        fontWeight: FontWeight.w300,

                      ),
                      textAlign: TextAlign.center,
                    ),


                      //게이지 비활성 25.12.11
                      /*Container(
                        width: w * 0.9,
                        height: portrait ? h * 0.13 : h * 2,
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          spacing: w * 0.1,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: w * 0.3,
                              child: GaugeTile(
                                title: '전류1',
                                isInt: false,
                                value: currentP1,
                                unit: 'A',
                                max: 60,
                                size: w * 0.3,
                                color: AppColor.duBlue,
                              ),
                            ),
                            SizedBox(
                              width: w * 0.3,
                              child: GaugeTile(
                                title: '전류2',
                                isInt: false,
                                value: currentP2,
                                unit: 'A',
                                max: 60,
                                size: w * 0.3,
                                color: AppColor.duGreen,
                              ),
                            ),
                          ],
                        ),
                      ),*/
                      const SizedBox(height: 16),

                      // 전류 히스토리 그래프 (한 화면 30분, 스크롤로 60분)
                      //최대 전류 표시 60A
                      SizedBox(
                        height: h * 0.35,
                        child: _PowerHistoryChart(powerLimit: powerLimit.toInt()),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ───────── 설정 섹션: 과전류 설정/ 과전류(EOCR) 알람지연 /전류 편차  ─────────
            if(hasAdminAccess)...[
              SettingsSection(
              margin: const EdgeInsetsDirectional.only(top: 4, bottom: 100),
              title: const Text('전류 설정'),
              tiles: [
                SettingsTile.navigation(
                  leading: const Icon(Icons.bolt),
                  title: const Text('과전류 설정값'),
                  value: Text('${powerLimitA.toStringAsFixed(1)} A'),
                  onPressed: (_) async {
                    // 초기 값: 레지스터 20~400 → 2.0~40.0
                    final controller = TextEditingController(
                      text: powerLimitA.toStringAsFixed(1),
                    );

                    final newA = await showDialog<double>(
                      context: context,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text('과전류 값 설정'),
                          content: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: false,
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              hintText: '2.0 ~ 40.0 (A)',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('취소', style: TextStyle(color: AppColor.duBlue),),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColor.duBlue),
                              onPressed: () {
                                final rawText = controller.text.trim();
                                final parsed = double.tryParse(rawText);

                                // 🔹 숫자 아님
                                if (parsed == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('숫자를 입력해 주세요.')),
                                  );
                                  return;
                                }

                                // 🔹 범위 밖 (2.0 ~ 40.0A)
                                if (parsed < 2.0 || parsed > 40.0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('2.0 ~ 40.0 범위의 값을 입력해 주세요.')),
                                  );
                                  return;
                                }

                                // ✅ 문제 없으면 실전류 값(A) 그대로 반환 (예: 2.1)
                                Navigator.of(ctx).pop(parsed);
                              },
                              child: const Text('저장'),
                            ),
                          ],

                        );
                      },
                    );

                    // 사용자가 취소한 경우
                    if (newA == null || !mounted) return;

                    // 🔹 newA는 2.1 같은 실전류 값, 여기서 레지스터 값으로 변환
                    final scaled = (newA * 10).round().clamp(20, 400);

                    final ok = await widget.writeRegister(32, scaled);
                    if (!ok || !mounted) return;

                    setState(() {
                      _powerLimit = scaled; // 🔹 내부 상태는 레지스터 값 그대로 유지
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('과전류 값이 ${newA.toStringAsFixed(1)}A 로 저장되었습니다.')),
                    );
                  },

                ),
                // 과전류 알람지연(EOCR 지연) 추가 25.12.11
               //  final powerDelay = _powerDelay!;
                SettingsTile.navigation(
                  leading: const Icon(Icons.timer),
                  title: const Text('과전류 알람지연'),
                  value: Text('$powerDelay 초'),
                  onPressed: (_) async {
                    final saved = await showRegisterNumberEditor(
                      context: context,
                      title: '과전류 알람지연 설정',
                      icon: Icons.timer,
                      address: 41,
                      initialValue: powerDelay,
                      writeRegister: widget.writeRegister,
                      min: 0,
                      max: 60,
                      accentColor: AppColor.duBlue,
                      hintText: '0 ~ 60',
                    );
                    if (saved != null && mounted) {
                      setState(() => _powerDelay = saved);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('과전류 알람지연이 저장되었습니다.')),
                      );
                    }
                  },
                ),
                //세팅 방법 변경 - 25.12.11
                SettingsTile.navigation(
                  leading: const Icon(Icons.compare_arrows),
                  title: const Text('전류 편차'),
                  value: Text('${powerDiffA.toStringAsFixed(1)} A'),//변수
                  onPressed: (_) async {
                    // 초기 값: 레지스터 0~300 → 0.0~30.0
                    final controller = TextEditingController(
                      text: powerDiffA.toStringAsFixed(1),//변수
                    );

                    final newA = await showDialog<double>(
                      context: context,
                      builder: (ctx) {
                        return AlertDialog(
                          title: const Text('전류 편차 설정'),
                          content: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: false,
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0.0 ~ 30.0 (A)',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('취소', style: TextStyle(color: AppColor.duBlue),),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColor.duBlue),
                              onPressed: () {
                                final rawText = controller.text.trim();
                                final parsed = double.tryParse(rawText);

                                // 🔹 숫자 아님
                                if (parsed == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('숫자를 입력해 주세요.')),
                                  );
                                  return;
                                }

                                // 🔹 범위 밖 (0.0 ~ 30.0A)
                                if (parsed < 0.0 || parsed > 30.0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('0.0 ~ 30.0 범위의 값을 입력해 주세요.')),
                                  );
                                  return;
                                }

                                // ✅ 문제 없으면 실전류 값(A) 그대로 반환 (예: 2.1)
                                Navigator.of(ctx).pop(parsed);
                              },
                              child: const Text('저장'),
                            ),
                          ],

                        );
                      },
                    );

                    // 사용자가 취소한 경우
                    if (newA == null || !mounted) return;

                    // 🔹 newA는 2.1 같은 실전류 값, 여기서 레지스터 값으로 변환
                    final scaled = (newA * 10).round().clamp(0, 300);

                    final ok = await widget.writeRegister(44, scaled); // --주소
                    if (!ok || !mounted) return;

                    setState(() {
                      _powerDiff = scaled; // 🔹 내부 상태는 레지스터 값 그대로 유지 --변수
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('전류 편차 값이 ${newA.toStringAsFixed(1)}A 로 저장되었습니다.')),
                    );
                  },

                ),
                /*SettingsTile.navigation(
                  leading: const Icon(Icons.compare_arrows),
                  title: const Text('전류 편차'),
                  value: Text('$powerDiff A'),
                  onPressed: (_) async {
                    final saved = await showRegisterNumberEditor(
                      context: context,
                      title: '전류 편차 설정',
                      icon: Icons.compare_arrows,
                      address: 44,
                      initialValue: powerDiff,
                      writeRegister: widget.writeRegister,
                      min: 0,
                      max: 300, //실수 설정 가능하도록 변경할 것
                      accentColor: AppColor.duBlue,
                      hintText: '0 ~ 30.0 (A)',
                    );
                    if (saved != null && mounted) {
                      setState(() => _powerDiff = saved);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('전류 편차가 저장되었습니다.')),
                      );
                    }
                  },
                ),*/
              ],
            ),
            ] else ...[
              SettingsSection(
                tiles: [
                  CustomSettingsTile(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_person_outlined, size: 50, color: AppColor.duLightGrey),
                          const SizedBox(height: 16),
                          const Text(
                            "관리자 전용 메뉴",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColor.duBlack),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "이 메뉴를 사용하려면\n '연결 설정'에서 관리자 인증이 필요합니다.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColor.duGrey, height: 1.5),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: w * 0.5,
                            child: FilledButton(
                              onPressed: () {
                                Navigator.of(context).pushNamed(Routes.connectSettingPage);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColor.duBlue,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("인증하러 가기", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PowerHistoryChart extends StatefulWidget {
  final int powerLimit;

  const _PowerHistoryChart({
    super.key,
    required this.powerLimit,
  });

  @override
  State<_PowerHistoryChart> createState() => _PowerHistoryChartState();
}

class _PowerHistoryChartState extends State<_PowerHistoryChart> {
  static const double ABSOLUTE_MIN_Y = 0;
  static const double ABSOLUTE_MAX_Y = 60;

  // 전체 데이터 (~수집데이터)
  static const int TOTAL_CHART_MINUTES = 4;
  // 한 화면에 5분 보이기
  static const double VIEW_WINDOW_MINUTES = 4;

  @override
  Widget build(BuildContext context) {
    final sel = context.watch<SelectedDevice>().current;

    if (sel == null) {
      return const Center(child: Text('선택된 기기가 없습니다.'));
    }

    final host = sel.address;
    final unitId = sel.unitId;

    final powerHistory = context.watch<PowerHistory>();
    final history1 = powerHistory.pointsFor(host, unitId, 1);
    final history2 = powerHistory.pointsFor(host, unitId, 2);

    if (history1.isEmpty && history2.isEmpty) {
      return const Center(child: Text('최근 1시간 데이터가 없습니다.'));
    }

    final now = DateTime.now();
    final from = now.subtract(const Duration(minutes: TOTAL_CHART_MINUTES));

    // 최근 60분 데이터만 사용
    final recent1 = history1.where((p) => !p.time.isBefore(from)).toList();
    final recent2 = history2.where((p) => !p.time.isBefore(from)).toList();

    if (recent1.isEmpty && recent2.isEmpty) {
      return const Center(child: Text('최근 60분 데이터가 없습니다.'));
    }

    final spots1 = <FlSpot>[];
    final spots2 = <FlSpot>[];
    final values = <double>[];

    for (final p in recent1) {
      final minutes = p.time.difference(from).inSeconds / 60.0;
      final clamped = p.value
          .clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y)
          .toDouble();
      spots1.add(FlSpot(minutes, clamped));
      values.add(clamped);
    }

    for (final p in recent2) {
      final minutes = p.time.difference(from).inSeconds / 60.0;
      final clamped = p.value
          .clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y)
          .toDouble();
      spots2.add(FlSpot(minutes, clamped));
      values.add(clamped);
    }

    // Y축 자동 범위 계산
    double dataMin = values.reduce((a, b) => a < b ? a : b);
    double dataMax = values.reduce((a, b) => a > b ? a : b);

    dataMin -= 1;
    dataMax += 1;

    double chartMinY =
    dataMin.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y).toDouble();
    double chartMaxY =
    dataMax.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y).toDouble();

    const double MINIMUM_VISIBLE_RANGE = 5.0;

    double range = chartMaxY - chartMinY;
    if (range < MINIMUM_VISIBLE_RANGE) {
      double center = (chartMaxY + chartMinY) / 2.0;

      chartMinY = (center - MINIMUM_VISIBLE_RANGE / 2.0)
          .clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);
      chartMaxY = (center + MINIMUM_VISIBLE_RANGE / 2.0)
          .clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);

      if (chartMaxY - chartMinY < MINIMUM_VISIBLE_RANGE) {
        chartMinY = chartMaxY - MINIMUM_VISIBLE_RANGE;
        chartMinY = chartMinY.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);
      }
    }

    chartMinY = (chartMinY - 1).clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);
    chartMaxY = (chartMaxY + 1).clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y);

    const double yInterval = 1.0;
    final double limitY = (widget.powerLimit / 10.0)
        .clamp(chartMinY, chartMaxY);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewWidth = constraints.maxWidth-15;
        final chartWidth =
            viewWidth * (TOTAL_CHART_MINUTES / VIEW_WINDOW_MINUTES);
        final limitA = widget.powerLimit / 10.0;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: TOTAL_CHART_MINUTES.toDouble(), // 0~60분
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
                        final dt =
                        from.add(Duration(seconds: (x * 2).round()));
                        final hh = dt.hour.toString().padLeft(2, '0');
                        final mm = dt.minute.toString().padLeft(2, '0');
                        final value = barSpot.y.toStringAsFixed(1);

                        final isP1 = barSpot.barIndex == 0;
                        final labelHead = isP1 ? '전류1' : '전류2';

                        return LineTooltipItem(
                          '$hh:$mm  ($labelHead)\n',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                          children: [
                            TextSpan(
                              text: '$value A',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w400,
                                fontSize: 10,
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
                        if (value.toInt() % 1 != 0) {
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
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        // 범위 밖이면 표시 안 함
                        if (value < 0 || value > TOTAL_CHART_MINUTES) {
                          return const SizedBox.shrink();
                        }

                        // 🔹 오른쪽 끝 레이블은 잘리니까 표시 안 함
                        /*
                        if ((TOTAL_CHART_MINUTES - value).abs() < 0.1) {
                          // value == TOTAL_CHART_MINUTES 인 경우
                          return const SizedBox.shrink();
                        }*/

                        final dt = from.add(
                          Duration(seconds: (value * 2).round()),
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
                    HorizontalLine(
                      y: limitY,
                      color: AppColor.duRed,
                      strokeWidth: 1.5,
                      dashArray: const [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.bottomRight,
                        labelResolver: (_) =>
                        '과전류 ${limitA.toStringAsFixed(1)}A',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColor.duRed,
                        ),
                      ),
                    ),
                  ],
                ),
                lineBarsData: [
                  // 전류1: duBlue
                  LineChartBarData(
                    spots: spots1,
                    isCurved: true,
                    gradient: LinearGradient(
                      colors: [
                        AppColor.duBlue,
                        AppColor.duBlue.withOpacity(0.5),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColor.duBlue.withAlpha(30),
                          AppColor.duBlue.withAlpha(0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),

                  // 전류2: duGreen
                  LineChartBarData(
                    spots: spots2,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [
                        AppColor.duGreen,
                        Color(0xFF66BB6A),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColor.duGreen.withAlpha(30),
                          AppColor.duGreen.withAlpha(0),
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
