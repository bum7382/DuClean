import 'package:flutter/material.dart';
import 'package:duclean/res/Constants.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:duclean/common/context_extensions.dart';

import 'package:duclean/providers/dp_history.dart';
import 'package:duclean/pages/Main.dart'; // GaugeTile() 이 이 파일에 있다면 추가

class DpDetailPage extends StatelessWidget {
  const DpDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<DpHistory>().points;

    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    // 세로 모드 여부
    final portrait = context.isPortrait;

    return Scaffold(
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
            : Column(
          children: [
            // 현재 차압 표시: GaugeTile 활용
            Builder(
              builder: (ctx) {
                final currentDp = history.last.value; // 가장 최근 차압

                return Container(
                  width: w * 0.8,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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

                  child: GaugeTile(title: '차압',  valueStr: currentDp.toString(), unit: 'mmAq', max: 500)
                );
              },
            ),
            const SizedBox(height: 16),

            // 차압 히스토리 라인 그래프
            const Expanded(
              child: _DpHistoryChart(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DpHistoryChart extends StatefulWidget {
  const _DpHistoryChart();

  @override
  State<_DpHistoryChart> createState() => _DpHistoryChartState();
}

class _DpHistoryChartState extends State<_DpHistoryChart> {
  // 1. Y축 상태 변수 정의 및 초기 설정
  double minChartY = 0;
  double maxChartY = 100; // 초기 0~100mmAq
  double touchStartDY = 0;
  double touchStartMaxY = 0;
  double touchStartMinY = 0;

  static const double ABSOLUTE_MIN_Y = 0;
  static const double ABSOLUTE_MAX_Y = 500;
  static const double Y_SCROLL_SENSITIVITY = 1.5;

  // X축 스크롤 설정
  static const double TOTAL_CHART_MINUTES = 20;
  static const double CHART_BASE_WIDTH = 800; // 20분 전체를 담을 고정 너비

  // Y축을 100단위로 깔끔하게 맞추기 위한 로직 (유지)
  void _snapYAxis(double newMin, double newMax) {
    double clampedMin = newMin.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y - (maxChartY - minChartY));
    double clampedMax = newMax.clamp(ABSOLUTE_MIN_Y + (maxChartY - minChartY), ABSOLUTE_MAX_Y);

    final chartRange = maxChartY - minChartY;

    if (clampedMax > ABSOLUTE_MAX_Y) {
      clampedMax = ABSOLUTE_MAX_Y;
      clampedMin = clampedMax - chartRange;
    }
    if (clampedMin < ABSOLUTE_MIN_Y) {
      clampedMin = ABSOLUTE_MIN_Y;
      clampedMax = clampedMin + chartRange;
    }

    setState(() {
      minChartY = clampedMin.roundToDouble(); // 정수 단위로 조정
      maxChartY = clampedMax.roundToDouble(); // 정수 단위로 조정
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<DpHistory>().points;
    final chartHeight = context.size?.height ?? 300; // 차트의 높이를 가져옵니다.

    if (history.isEmpty) {
      return const Center(child: Text('최근 20분 데이터가 없습니다.'));
    }

    final now = DateTime.now();
    // const Duration 제거 오류 해결
    final from = now.subtract(Duration(minutes: TOTAL_CHART_MINUTES.toInt()));

    final recent = history.where((p) => !p.time.isBefore(from)).toList();

    if (recent.isEmpty) {
      return const Center(child: Text('최근 20분 데이터가 없습니다.'));
    }

    final spots = <FlSpot>[];
    for (final p in recent) {
      final minutes = p.time.difference(from).inSeconds / 60.0;
      final clamped = p.value.clamp(ABSOLUTE_MIN_Y, ABSOLUTE_MAX_Y).toDouble();
      spots.add(FlSpot(minutes, clamped));
    }

    // Y축 드래그 처리 및 X축 스크롤 처리 결합
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // 최신 데이터부터 보기
      child: SizedBox(
        width: CHART_BASE_WIDTH, // X축 스크롤을 위한 고정 너비
        // Y축 드래그 이벤트만 처리하도록 GestureDetector 추가
        child: GestureDetector(
          onVerticalDragStart: (details) {
            touchStartDY = details.localPosition.dy;
            touchStartMaxY = maxChartY;
            touchStartMinY = minChartY;
          },
          onVerticalDragUpdate: (details) {
            final diffY = touchStartDY - details.localPosition.dy;
            final chartRange = touchStartMaxY - touchStartMinY;

            // 드래그 거리를 차트 높이 비율에 맞춰 변환
            final yChange = diffY / chartHeight * ABSOLUTE_MAX_Y * Y_SCROLL_SENSITIVITY;

            final newMinY = touchStartMinY - yChange;
            final newMaxY = newMinY + chartRange;

            _snapYAxis(newMinY, newMaxY);
          },
          child: LineChart(
            LineChartData(
              // ───── X/Y 축 범위 ─────
              minX: 0,
              maxX: TOTAL_CHART_MINUTES,
              minY: minChartY,
              maxY: maxChartY,

              // ───── 터치/툴팁 설정 (기존 유지) ─────
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

              // ───── 격자/경계 설정 ─────
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                drawVerticalLine: false,

                // 300일 때만 다른 색상과 두께를 적용
                getDrawingHorizontalLine: (value) {
                  if (value == 300) {
                    return const FlLine(
                      color: Colors.redAccent, // 경고 레벨 색상
                      strokeWidth: 1.5,
                      dashArray: [5, 5], // 파선으로 표시
                    );
                  }
                  // 기본 격자선 스타일 (얇고 어두운 색상)
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

              // ───── 축 라벨 설정 (기존 유지) ─────
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    // Y축 간격 조정
                    interval: (maxChartY - minChartY) > 200 ? 100 : 50,
                    getTitlesWidget: (value, meta) {
                      // 100 단위만 표시 (기존 유지)
                      if (value.toInt() % 100 != 0) {
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
                      if (value < 0 || value > TOTAL_CHART_MINUTES) {
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

              // ───── 라인 바 데이터 (스타일 적용) ─────
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  // 1. 그라데이션 적용
                  gradient: LinearGradient(
                    colors: [
                      AppColor.duBlue, // 듀 클린 블루
                      AppColor.duBlue.withOpacity(0.5),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  barWidth: 3, // 선 굵기 조정
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),

                  // 2. 아래 영역 채우기 (LineChartSample2 스타일)
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        AppColor.duBlue.withOpacity(0.3),
                        AppColor.duBlue.withOpacity(0.0),
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
      ),
    );
  }
}

