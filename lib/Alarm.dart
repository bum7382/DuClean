import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duclean/res/Constants.dart';

const String _kAlarmCodeKey = 'alarm_current_code';
const String _kAlarmDateKey = 'alarm_current_date_ms';

/// 알람 히스토리 키
const String _kAlarmHistKey = 'alarm_history';

const String _defaultDeviceName = 'AP-500';

String _alarmMessage(int code) {
  switch (code) {
    case 1: return '과전류';
    case 2: return '운전에러';
    case 3: return '모터 역방향';
    case 4: return '전류 불평형';
    case 5: return '과차압';
    case 6: return '필터교체';
    case 7: return '저차압';
    default: return '알람 없음';
  }
}

String _formatKTime(DateTime ts) {
  final d = ts.toLocal();
  final am = d.hour < 12 ? '오전' : '오후';
  final h12 = (d.hour % 12 == 0) ? 12 : (d.hour % 12);
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.month}월 ${d.day}일 $am ${h12}시 ${mm}분';
}

class _AlarmEntry {
  final int code;
  final int tsMs; // epoch ms
  const _AlarmEntry({required this.code, required this.tsMs});

  Map<String, dynamic> toJson() => {'code': code, 'ts': tsMs};
  static _AlarmEntry? fromJson(Map<String, dynamic> m) {
    final ts = (m['ts'] as num?)?.toInt();
    final code = (m['code'] as num?)?.toInt();
    if (ts == null || code == null) return null;
    return _AlarmEntry(code: code, tsMs: ts);
  }
}

class _LoadedData {
  final List<_AlarmEntry> entries; // 최신순
  final int? latestCode;
  final int? latestTs;
  _LoadedData(this.entries, this.latestCode, this.latestTs);
}

class AlarmPage extends StatelessWidget {
  const AlarmPage({super.key});

  Future<_LoadedData> _loadAndMaybeAppend() async {
    final prefs = await SharedPreferences.getInstance();

    // 최신값 읽기
    final latestCode = prefs.getInt(_kAlarmCodeKey);
    final latestTs = prefs.getInt(_kAlarmDateKey);

    // 기존 히스토리 로드
    final raw = prefs.getStringList(_kAlarmHistKey) ?? const <String>[];
    final parsed = <_AlarmEntry>[];
    for (final s in raw) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        final e = _AlarmEntry.fromJson(map);
        if (e != null) parsed.add(e);
      } catch (_) {/* skip */}
    }

    // 최신값이 있고(code != 0) 아직 히스토리에 없으면 1건 추가
    if (latestCode != null && latestTs != null && latestCode != 0) {
      final exists = parsed.any((e) => e.tsMs == latestTs && e.code == latestCode);
      if (!exists) {
        parsed.add(_AlarmEntry(code: latestCode, tsMs: latestTs));
        // 용량 제한
        const maxKeep = 500;
        if (parsed.length > maxKeep) {
          parsed.sort((a, b) => a.tsMs.compareTo(b.tsMs));
          parsed.removeRange(0, parsed.length - maxKeep);
        }
        // 저장
        final toSave = parsed.map((e) => jsonEncode(e.toJson())).toList();
        await prefs.setStringList(_kAlarmHistKey, toSave);
      }
    }

    // 최신순 정렬
    parsed.sort((a, b) => b.tsMs.compareTo(a.tsMs));
    return _LoadedData(parsed, latestCode, latestTs);
  }

  @override
  Widget build(BuildContext context) {
    // 기기 이름 인자
    String deviceName = _defaultDeviceName;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      deviceName = args['name'] as String? ?? deviceName;
    } else if (args is String) {
      deviceName = args;
    }

    return Scaffold(
      backgroundColor: const Color(0xfff6f6f6),
      appBar: AppBar(
        centerTitle: true,
        title: const Text('알람 내역',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppColor.duBlue,
      ),
      body: FutureBuilder<_LoadedData>(
        future: _loadAndMaybeAppend(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final entries = data.entries;

          if (entries.isEmpty) {
            return const Center(
              child: Text('알람 내역이 없습니다.', style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final e = entries[i];
              final time = DateTime.fromMillisecondsSinceEpoch(e.tsMs).toLocal();
              final timeText = _formatKTime(time);
              final msg = _alarmMessage(e.code);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 왼쪽: 기기명 + 시간
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(deviceName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600, color: AppColor.duBlue)),
                          const SizedBox(height: 4),
                          Text(timeText, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                    // 오른쪽: 알람 메시지
                    Text(msg, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
