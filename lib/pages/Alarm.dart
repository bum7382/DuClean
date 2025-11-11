import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duclean/res/Constants.dart';
// import 'package:mqtt_client/mqtt_client.dart';
// import 'package:mqtt_client/mqtt_server_client.dart';

const String _kAlarmCodeKey = 'alarm_current_code';
const String _kAlarmDateKey = 'alarm_current_date_ms';
const String _kAlarmClearedSourceTsKey = 'alarm_cleared_source_ts_ms';
const String _kAlarmClearedCodeKey    = 'alarm_cleared_code';
const String _kAlarmClearedAtKey      = 'alarm_cleared_at_ms';

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
  final int code;          // 발생 코드(1~7)
  final int tsMs;          // 발생 시각(epoch ms)
  final int? clearedTsMs;  // 해제 시각(epoch ms), 없으면 미해제

  const _AlarmEntry({
    required this.code,
    required this.tsMs,
    this.clearedTsMs,
  });

  _AlarmEntry copyWith({int? code, int? tsMs, int? clearedTsMs}) {
    return _AlarmEntry(
      code: code ?? this.code,
      tsMs: tsMs ?? this.tsMs,
      clearedTsMs: clearedTsMs ?? this.clearedTsMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'ts': tsMs,
    if (clearedTsMs != null) 'cleared_ts': clearedTsMs,
  };

  static _AlarmEntry? fromJson(Map<String, dynamic> m) {
    final ts = (m['ts'] as num?)?.toInt();
    final code = (m['code'] as num?)?.toInt();
    final cleared = (m['cleared_ts'] as num?)?.toInt();
    if (ts == null || code == null) return null;
    return _AlarmEntry(code: code, tsMs: ts, clearedTsMs: cleared);
  }
}


class _LoadedData {
  final List<_AlarmEntry> entries; // 최신순
  final int? latestCode;
  final int? latestTs;
  _LoadedData(this.entries, this.latestCode, this.latestTs);
}

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}



class _AlarmPageState extends State<AlarmPage> {
  late Stream<_LoadedData> _stream;

  /*
  final String broker = "broker.hivemq.com";     // MQTT broker address
  final int port = 1883;                 // MQTT broker port
  final String topic = "alarm";           // MQTT topic

  MqttServerClient? client;
  bool connected = false;
  */

  @override
  void initState() {
    super.initState();
    _stream = _alarmStream(); // 페이지가 보이는 동안 1초 주기로 새로고침
    // setupMqtt();
  }

  /*
  Future<void> setupMqtt() async {
    // MQTT 브로커 연결
    client = MqttServerClient.withPort(broker, 'flutter_client', port);
    // MQTT 로그 출력
    client!.logging(on: false);

    // 리스너 등록
    client!.onConnected = onMqttConnected;
    // client!.onDisconnected = onMqttDisconnected;
    // client!.onSubscribed = onSubscribed;

    try {
      //
      await client!.connect();
    } catch (e) {
      print('Connected Failed.. \nException: $e');
    }
  }

  void onMqttConnected() {
    print(':: MqttConnected');
    setState(() {
      connected = true;
      // MQTT 연결 시 토픽 구독.
      client!.subscribe(topic, MqttQos.atLeastOnce);

      // 토픽 수신 리스너
      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String message =
        MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        // 수신한 메시지 처리
        setState(() {
          print(':: Received message: $message');
        });
      });
    });
  }
  */


  // 1초마다 SharedPreferences를 다시 읽음
  Stream<_LoadedData> _alarmStream() async* {
    while (mounted) {
      yield await _loadAndMaybeAppend();
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<_LoadedData> _loadAndMaybeAppend() async {
    final prefs = await SharedPreferences.getInstance();

    // 최신값 읽기
    final latestCode = prefs.getInt(_kAlarmCodeKey);
    final latestTs   = prefs.getInt(_kAlarmDateKey);

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

    bool touched = false;

    // 최신 발생값이 있고 아직 없으면 append
    if (latestCode != null && latestTs != null && latestCode != 0) {
      final exists = parsed.any((e) => e.tsMs == latestTs && e.code == latestCode);
      if (!exists) {
        parsed.add(_AlarmEntry(code: latestCode, tsMs: latestTs));
        touched = true;
      }
    }

    // 해제 신호 병합
    final clearedSourceTs = prefs.getInt(_kAlarmClearedSourceTsKey);
    final clearedCode     = prefs.getInt(_kAlarmClearedCodeKey);
    final clearedAtMs     = prefs.getInt(_kAlarmClearedAtKey);

    if (clearedSourceTs != null && clearedAtMs != null) {
      int idx = -1;
      // 1순위: (ts, code) 동시 일치
      if (clearedCode != null) {
        idx = parsed.indexWhere((e) => e.tsMs == clearedSourceTs && e.code == clearedCode);
      }
      // 2순위: ts만 일치
      if (idx == -1) {
        idx = parsed.indexWhere((e) => e.tsMs == clearedSourceTs);
      }
      // 3순위: code 일치 & 아직 미해제인 최신 건
      if (idx == -1 && clearedCode != null) {
        idx = parsed.indexWhere((e) => e.code == clearedCode && e.clearedTsMs == null);
      }

      if (idx != -1 && parsed[idx].clearedTsMs == null) {
        parsed[idx] = parsed[idx].copyWith(clearedTsMs: clearedAtMs);
        touched = true;
      }

      // 해제 신호는 1회용 → 소모
      await prefs.remove(_kAlarmClearedSourceTsKey);
      await prefs.remove(_kAlarmClearedCodeKey);
      await prefs.remove(_kAlarmClearedAtKey);
    }

    // 용량 제한(오래된 것 제거)
    const maxKeep = 500;
    if (parsed.length > maxKeep) {
      parsed.sort((a, b) => a.tsMs.compareTo(b.tsMs));
      parsed.removeRange(0, parsed.length - maxKeep);
      touched = true;
    }

    // 변경되었으면 저장
    if (touched) {
      final toSave = parsed.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_kAlarmHistKey, toSave);
    }

    // 최신순 정렬 후 반환
    parsed.sort((a, b) => b.tsMs.compareTo(a.tsMs));
    return _LoadedData(parsed, latestCode, latestTs);
  }


  @override
  Widget build(BuildContext context) {
    // 기기 이름 인자
    String? _resolveDeviceName(BuildContext context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        return args['name'] as String?;
      } else if (args is String) {
        return args;
      }
      return null;
    }

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        centerTitle: false,
        title: const Text('알람 내역',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: AppColor.duBlue,
      ),
      body: StreamBuilder<_LoadedData>(
        stream: _stream,
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

          return RefreshIndicator(
            onRefresh: () async {
              setState(() { _stream = _alarmStream(); });
              await Future.delayed(const Duration(milliseconds: 300));
            },
            edgeOffset: 10, // Indicator 생성위치
            displacement: 10, // Indicator 최종 위치
            color: Colors.white, // Indicator 색상
            backgroundColor: AppColor.duBlue,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = entries[i];

                final occurredAt = DateTime.fromMillisecondsSinceEpoch(e.tsMs).toLocal();
                final occurredText = _formatKTime(occurredAt);

                final clearedAt = (e.clearedTsMs != null)
                    ? DateTime.fromMillisecondsSinceEpoch(e.clearedTsMs!).toLocal()
                    : null;
                final clearedText = (clearedAt != null) ? _formatKTime(clearedAt) : null;

                final msg = _alarmMessage(e.code);
                final isCleared = clearedAt != null;

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
                            Text(
                              _resolveDeviceName(context) ?? _defaultDeviceName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: isCleared ? Colors.grey : AppColor.duBlue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text("발생: $occurredText",
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            if (isCleared) ...[
                              const SizedBox(height: 2),
                              Text("해제: $clearedText",
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ],
                        ),
                      ),
                      // 오른쪽: 알람 메시지
                      Text( msg,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isCleared ? Colors.grey : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}