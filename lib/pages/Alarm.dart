import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/services/alarm_store.dart';
import 'package:duclean/common/context_extensions.dart';
// import 'package:mqtt_client/mqtt_client.dart';
// import 'package:mqtt_client/mqtt_server_client.dart';



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

class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}



class _AlarmPageState extends State<AlarmPage> {
  late Stream<List<AlarmRecord>> _stream;

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


  Stream<List<AlarmRecord>> _alarmStream() async* {
    while (mounted) {
      yield await AlarmStore.loadAllSortedDesc();
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _onDeleteAllPressed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('알람 내역 삭제'),
          content: const Text('알람 내역을 모두 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소', style: TextStyle(color: Colors.black87)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    ) ?? false;

    if (!ok) return;

    // 실제 삭제
    await AlarmStore.clearAll();

    // 화면 갱신 (Stream 재시작)
    if (!mounted) return;
    setState(() {
      _stream = _alarmStream();
    });
  }


  @override
  Widget build(BuildContext context) {

    // 화면 크기
    final w = context.screenWidth;
    final h = context.screenHeight;

    // 세로 모드 여부
    final portrait = context.isPortrait;

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
        actions: [
          Padding(
            padding: EdgeInsetsGeometry.only(right: w * 0.04),
            child:
              IconButton(
                onPressed: _onDeleteAllPressed,
                icon: Icon(Icons.delete, color: Colors.white, size: 30,)
              )

          )

        ],
        backgroundColor: AppColor.duBlue,
      ),
      body: StreamBuilder<List<AlarmRecord>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = snap.data!;
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
            edgeOffset: 10,
            displacement: 10,
            color: Colors.white,
            backgroundColor: AppColor.duBlue,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = entries[i];

                final occurredAt  = DateTime.fromMillisecondsSinceEpoch(e.tsMs).toLocal();
                final occurredTxt = _formatKTime(occurredAt);

                final clearedAt   = (e.clearedTsMs != null)
                    ? DateTime.fromMillisecondsSinceEpoch(e.clearedTsMs!).toLocal()
                    : null;
                final clearedTxt  = (clearedAt != null) ? _formatKTime(clearedAt) : null;

                final msg = _alarmMessage(e.code);
                final isCleared = clearedAt != null;


                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(4),
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
                            Column(
                              textBaseline: TextBaseline.alphabetic,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              spacing: 5,
                              children: [
                                Text(
                                  e.name, style: TextStyle( fontSize: 11, fontWeight: FontWeight.w300,
                                    color: isCleared ? Colors.grey : AppColor.duBlue,
                                  ),
                                ),
                                Text(
                                   e.host, style: TextStyle( fontSize: 10, fontWeight: FontWeight.w300,
                                  color: isCleared ? Colors.grey : Colors.black,
                                ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text("발생: $occurredTxt",
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            if (isCleared) ...[
                              const SizedBox(height: 2),
                              Text("해제: $clearedTxt",
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ],
                        ),
                      ),
                      // 오른쪽: 알람 메시지
                      Text(
                        msg,
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