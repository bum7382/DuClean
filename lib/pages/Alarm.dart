import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/services/alarm_store.dart';
import 'package:duclean/common/context_extensions.dart';

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

  // 필터링을 위한 변수
  String? _targetHost;
  String? _targetName;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // initState에서는 context를 통해 arguments를 가져올 수 없으므로 여기서 처리
    if (!_isInit) {
      _extractArguments();
      _stream = _alarmStream(); // 인자 확인 후 스트림 생성
      _isInit = true;
    }
  }

  /// 네비게이션 인자(Arguments) 추출
  void _extractArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;

    // 1. Map 형태로 넘어온 경우
    if (args is Map<String, dynamic>) {
      _targetHost = args['host']; // 예: '192.168.0.10'
      _targetName = args['name']; // 예: 'AP-500'
    }
    // 2. DeviceKey 객체(혹은 dynamic)로 넘어온 경우
    else if (args != null) {
      try {
        final dynamic d = args;
        _targetHost = d.host;
        _targetName = d.name;
      } catch (_) {
        // 구조가 다르면 무시 (전체 알람 표시)
      }
    }
  }

  Stream<List<AlarmRecord>> _alarmStream() async* {
    while (mounted) {
      // 1. 전체 데이터 로드
      List<AlarmRecord> allRecords = await AlarmStore.loadAllSortedDesc();

      // 2. 선택된 기기가 있다면 필터링 (Host IP 기준)
      if (_targetHost != null && _targetHost!.isNotEmpty) {
        final filtered = allRecords.where((e) => e.host == _targetHost).toList();
        yield filtered;
      } else {
        // 선택된 기기가 없으면 전체 표시
        yield allRecords;
      }

      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _onDeleteAllPressed() async {
    // 다이얼로그 메시지 분기 처리
    final String contentMsg = _targetName != null
        ? '$_targetName의 알람 내역을\n모두 삭제하시겠습니까?'
        : '저장된 모든 알람 내역을 삭제하시겠습니까?';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('알람 내역 삭제'),
          content: Text(contentMsg),
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

    // [수정됨] 기기 선택 여부에 따라 삭제 로직 분기
    if (_targetHost != null && _targetHost!.isNotEmpty) {
      // 1. 특정 기기 알람만 삭제
      // 주의: AlarmStore에 deleteByHost 메서드가 없으면 에러가 납니다. (하단 참고)
      await AlarmStore.deleteByHost(_targetHost!);
    } else {
      // 2. 전체 삭제 (기존 로직)
      await AlarmStore.clearAll();
    }

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

    // 타이틀: 기기 이름이 있으면 해당 이름 표시
    final titleText = _targetName != null ? '$_targetName 알람' : '알람 내역';

    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        centerTitle: false,
        title: Text(titleText,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
              padding: EdgeInsetsGeometry.only(right: w * 0.04),
              child: IconButton(
                onPressed: _onDeleteAllPressed,
                icon: const Icon(Icons.delete, color: Colors.white, size: 30),
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
                        color: Colors.black.withAlpha(10),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.name,
                                  style: TextStyle( fontSize: 11, fontWeight: FontWeight.w300,
                                    color: isCleared ? Colors.grey : AppColor.duBlue,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  e.host,
                                  style: TextStyle( fontSize: 10, fontWeight: FontWeight.w300,
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