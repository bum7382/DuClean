// lib/pages/schedule/ScheduleEdit.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/res/customWidget.dart';
import 'package:material_symbols_icons/symbols.dart';

// 일정 추가/수정 페이지
class ScheduleEditPage extends StatefulWidget {
  const ScheduleEditPage({
    super.key,
    this.initial,
  });

  final MotorScheduleEntry? initial;

  @override
  State<ScheduleEditPage> createState() => _ScheduleEditPageState();
}

class _ScheduleEditPageState extends State<ScheduleEditPage> {
  late bool _isOn;                 // 켬/끔 선택
  TimeOfDay? _time;                // 시간
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7}; // 기본: 매일
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _isOn = init.isOn;
      _time = init.time;
      _weekdays = {...init.weekdays};
      _enabled = init.enabled;
    } else {
      _isOn = true;
      _time = TimeOfDay.now();
      _weekdays = {1, 2, 3, 4, 5, 6, 7};
      _enabled = true;
    }
  }

  String _formatTime(TimeOfDay? t) {
    if (t == null) return '시간 선택';

    final period = t.hour >= 12 ? '오후' : '오전';
    final h = t.hourOfPeriod.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');

    return '$period $h:$m';
  }

  String _weekdayLabel(Set<int> weekdays) {
    if (weekdays.length == 7) return '매일';
    if (weekdays.isEmpty) return '반복 없음';
    final names = ['월', '화', '수', '목', '금', '토', '일'];
    final list = weekdays.toList()..sort();
    return list.map((d) => names[d - 1]).join(', ');
  }

  void _toggleWeekday(int d) {
    setState(() {
      if (_weekdays.contains(d)) {
        _weekdays.remove(d);
      } else {
        _weekdays.add(d);
      }
    });
  }

  void _setDaily() {
    setState(() {
      _weekdays = {1, 2, 3, 4, 5, 6, 7};
    });
  }

  Future<void> _save() async {
    if (_time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('시간을 설정하세요.')),
      );
      return;
    }

    final id = widget.initial?.id ??
        'schedule_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final entry = MotorScheduleEntry(
      id: id,
      enabled: _enabled,
      isOn: _isOn,
      time: _time!,
      weekdays: {..._weekdays},
    );

    Navigator.of(context).pop(entry);
  }

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    final h = context.screenHeight;

    final portrait = context.isPortrait;

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.duBlue,
        centerTitle: false,
        title: Text(
          widget.initial == null ? '일정 추가' : '일정 수정',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(w * 0.05),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 켬/끔 토글
              BgContainer(
                radius: 12,
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '동작',
                        style: TextStyle(
                            color: Colors.black, fontSize: w * 0.04),
                      ),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('켬'),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            label: Text('끔'),
                          ),
                        ],
                        selected: {_isOn},
                        style: ButtonStyle(
                          side: WidgetStateProperty.resolveWith(
                                (states) {
                              if (states.contains(WidgetState.selected)) {
                                return BorderSide.none;
                              }
                              return const BorderSide(
                                color: AppColor.duLightGrey,
                                width: 1.0,
                              );
                            },
                          ),
                          backgroundColor: WidgetStateProperty.resolveWith(
                                (states) {
                              if (states.contains(WidgetState.selected)) {
                                return AppColor.duBlue;
                              }
                              return Colors.white;
                            },
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                                (states) {
                              if (states.contains(WidgetState.selected)) {
                                return Colors.white;
                              }
                              return AppColor.duLightGrey;
                            },
                          ),
                        ),
                        onSelectionChanged: (set) {
                          setState(() {
                            _isOn = set.first;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: h * 0.02),
              // 시간 선택 (Cupertino picker)
              BgContainer(
                radius: 12,
                height: portrait ? h * 0.3 : h * 0.5,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                    _time?.hour ?? TimeOfDay.now().hour,
                    _time?.minute ?? TimeOfDay.now().minute,
                  ),
                  use24hFormat: false, // 오전/오후 표시
                  onDateTimeChanged: (DateTime newDate) {
                    setState(() {
                      _time = TimeOfDay.fromDateTime(newDate);
                    });
                  },
                ),
              ),
              SizedBox(height: h * 0.02),
              // 요일 선택
              BgContainer(
                radius: 12,
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '반복 요일',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('매일'),
                            selected: _weekdays.length == 7,
                            selectedColor: AppColor.duBlue,
                            showCheckmark: false,
                            side: BorderSide(
                              color: _weekdays.length == 7
                                  ? Colors.transparent
                                  : AppColor.duLightGrey,
                            ),
                            backgroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            labelStyle: TextStyle(
                              color: _weekdays.length == 7
                                  ? Colors.white
                                  : AppColor.duLightGrey,
                            ),
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  _setDaily();
                                } else {
                                  _weekdays.clear();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        children: List.generate(7, (index) {
                          final d = index + 1;
                          const names = ['월', '화', '수', '목', '금', '토', '일'];
                          final selected = _weekdays.contains(d);
                          return ChoiceChip(
                            label: Text(names[index]),
                            selected: selected,
                            selectedColor: AppColor.duBlue,
                            backgroundColor: Colors.white,
                            shape: const CircleBorder(),
                            showCheckmark: false,
                            side: BorderSide(
                              color: selected
                                  ? Colors.transparent
                                  : AppColor.duLightGrey,
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : AppColor.duLightGrey,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            onSelected: (_) => _toggleWeekday(d),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _weekdayLabel(_weekdays),
                        style: TextStyle(
                          color: AppColor.duLightGrey,
                          fontSize: w * 0.035,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: h * 0.02),
              // 일정 사용 여부
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '일정 사용',
                    style: TextStyle(
                        color: Colors.black, fontSize: w * 0.04),
                  ),
                  Switch(
                    value: _enabled,
                    activeTrackColor: AppColor.duBlue,
                    onChanged: (v) {
                      setState(() {
                        _enabled = v;
                      });
                    },
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.only(top: h * 0.05),
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColor.duBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _save,
                    child: Text(
                      '예약 저장',
                      style: TextStyle(fontSize: w * 0.04),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
