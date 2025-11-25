// lib/pages/schedule/Schedule.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:duclean/res/Constants.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/res/customWidget.dart';
import 'package:duclean/pages/schedule/ScheduleEdit.dart';
import 'package:material_symbols_icons/symbols.dart';

// SharedPreferences 키
const String _kSchedulesPrefsKey = 'motor_schedules_v1';

// 일정 목록 페이지
class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.writeRegister,
    required this.readRegister,
  });

  final Future<int?> Function(int address) readRegister;
  final Future<bool> Function(int address, int value) writeRegister;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final List<MotorScheduleEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntriesFromPrefs();
  }

  // ---------- SharedPreferences 저장/복구 ----------

  Future<void> _loadEntriesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kSchedulesPrefsKey);
    if (jsonStr == null || jsonStr.isEmpty) return;

    try {
      final List<dynamic> list = jsonDecode(jsonStr) as List<dynamic>;
      final loaded = list.map((e) {
        final m = e as Map<String, dynamic>;

        final hour = m['hour'] as int? ?? 0;
        final minute = m['minute'] as int? ?? 0;
        final List<dynamic> wdList = m['weekdays'] as List<dynamic>? ?? [];

        return MotorScheduleEntry(
          id: m['id'] as String,
          enabled: m['enabled'] as bool? ?? true,
          isOn: m['isOn'] as bool? ?? true,
          time: TimeOfDay(hour: hour, minute: minute),
          weekdays: wdList.map((x) => x as int).toSet(),
        );
      }).toList();

      setState(() {
        _entries
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      debugPrint('스케줄 목록 복구 실패: $e');
    }
  }

  Future<void> _saveEntriesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _entries.map((e) {
      return <String, dynamic>{
        'id': e.id,
        'enabled': e.enabled,
        'isOn': e.isOn,
        'hour': e.time.hour,
        'minute': e.time.minute,
        'weekdays': e.weekdays.toList(),
      };
    }).toList();

    final jsonStr = jsonEncode(list);
    await prefs.setString(_kSchedulesPrefsKey, jsonStr);
  }

  /// 공통 처리 훅
  Future<void> _onEntriesChanged() async {
    await _saveEntriesToPrefs();
    // 나중에 여기서 MotorScheduleService 연동
    // 예: MotorScheduleService().updateFromEntries(_entries);
  }

  String _weekdayLabel(Set<int> weekdays) {
    if (weekdays.length == 7) return '매일';
    if (weekdays.isEmpty) return '반복 없음';
    final names = ['월', '화', '수', '목', '금', '토', '일'];
    final list = weekdays.toList()..sort();
    return list.map((d) => names[d - 1]).join(', ');
  }

  // 오전/오후 h:mm 포맷
  String _formatKoreanTime(TimeOfDay time) {
    final isAm = time.hour < 12;
    final period = isAm ? '오전' : '오후';

    int h = time.hour;
    if (h == 0) {
      h = 12; // 0시 -> 오전 12시
    } else if (h > 12) {
      h = h - 12; // 13~23 -> 1~11
    }

    final minute = time.minute.toString().padLeft(2, '0');
    return '$period $h:$minute';
  }

  Future<void> _openAddPage() async {
    final result = await Navigator.of(context).push<MotorScheduleEntry>(
      MaterialPageRoute(
        builder: (_) => const ScheduleEditPage(
          initial: null,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _entries.add(result);
      });
      await _onEntriesChanged();
    }
  }

  Future<void> _openEditPage(int index) async {
    final current = _entries[index];
    final result = await Navigator.of(context).push<MotorScheduleEntry>(
      MaterialPageRoute(
        builder: (_) => ScheduleEditPage(
          initial: current,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _entries[index] = result;
      });
      await _onEntriesChanged();
    }
  }

  Future<void> _confirmDelete(int index) async {
    final entry = _entries[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColor.bg,
        title: const Text(
          '일정 삭제',
          style: TextStyle(color: AppColor.duBlue),
        ),
        content: Text(
          '${_formatKoreanTime(entry.time)} / ${_weekdayLabel(entry.weekdays)}\n이 일정을 삭제할까요?',
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '취소',
              style: TextStyle(color: Colors.black),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColor.duRed,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    ) ??
        false;

    if (!ok) return;

    setState(() {
      _entries.removeAt(index);
    });
    await _onEntriesChanged();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    final h = context.screenHeight;

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.duBlue,
        centerTitle: false,
        title: const Text(
          '일정',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _openAddPage,
          ),
        ],
      ),
      body: _entries.isEmpty
          ? const Center(
        child: Text(
          '등록된 일정이 없습니다.\n오른쪽 상단 + 버튼으로 일정을 추가하세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColor.duLightGrey),
        ),
      )
          : Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 1,
                color: AppColor.duLightGrey.withOpacity(0.4),
              ),
              itemBuilder: (ctx, idx) {
                final e = _entries[idx];
                final color = e.isOn ? AppColor.duBlue : Colors.white;

                return ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: w * 0.05,
                    vertical: h * 0.008,
                  ),
                  tileColor: Colors.white,
                  leading: Container(
                    width: w * 0.1,
                    height: w * 0.1,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      border: e.actionLabel == "켬"
                          ? null
                          : Border.all(
                        color: AppColor.duLightGrey,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      e.actionLabel == "켬"
                          ? Symbols.mode_fan
                          : Symbols.mode_fan_off,
                      color: e.actionLabel == "켬"
                          ? Colors.white
                          : AppColor.duLightGrey,
                      size: w * 0.05,
                    ),
                  ),
                  title: Text(
                    _formatKoreanTime(e.time),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    _weekdayLabel(e.weekdays),
                    style: const TextStyle(
                      color: AppColor.duLightGrey,
                      fontSize: 13,
                    ),
                  ),
                  trailing: Switch(
                    value: e.enabled,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColor.duBlue,
                    onChanged: (v) async {
                      setState(() {
                        e.enabled = v;
                      });
                      await _onEntriesChanged();
                    },
                  ),
                  onTap: () => _openEditPage(idx),
                  onLongPress: () => _confirmDelete(idx),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
