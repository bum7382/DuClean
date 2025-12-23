import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:duclean/res/Constants.dart';
import 'package:duclean/services/alarm_store.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const String _defaultDeviceName = 'AP-500';

// 백엔드 설정
String _backendBaseUrl = dotenv.env['API_URL'] ?? 'http://default-url.com';

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
  final d = ts;
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
  String? _targetMac;
  bool _isInit = false;

  bool _isSyncing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // initState에서는 context를 통해 arguments를 가져올 수 없으므로 여기서 처리
    if (!_isInit) {
      _extractArguments();
      _stream = _alarmStream(); // 인자 확인 후 스트림 생성

      // [추가] 화면 진입 시 백엔드 동기화 실행
      _syncWithServer();

      _isInit = true;
    }
  }

  /// 네비게이션 인자(Arguments) 추출
  void _extractArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;
    debugPrint(args.toString());
    if (args is Map<String, dynamic>) {
      try {
        _targetHost = args['host']; // 예: '192.168.0.10'
        _targetName = args['name']; // 예: 'AP-500'
        _targetMac = args['mac'];
      } catch (_) {
        // 구조가 다르면 무시 (전체 알람 표시)
      }
    }
  }

  // [추가] 백엔드 데이터 가져오기 및 로컬 저장
  // AlarmPage.dart 내의 수정된 부분

// 동기화 중복 실행 방지를 위한 플래그


// 1. 서버 동기화 함수 개선 (성공 여부 반환)
  Future<bool> _syncWithServer() async {
    if (_targetHost == null && _targetMac == null) return false;
    if (_isSyncing) return false; // 이미 동기화 중이면 중복 실행 방지

    _isSyncing = true;
    try {
      final Map<String, String> queryParams = {};
      if (_targetHost != null) queryParams['ip'] = _targetHost!;
      if (_targetMac != null) queryParams['mac'] = _targetMac!;

      // [중요] 과거 내역(연결 끊겼을 때 발생한 것)을 가져오려면
      // active=true 조건을 빼거나 서버가 전체를 주도록 해야 합니다.
      // queryParams['active'] = 'true'; // 이 줄을 주석 처리하거나 제거하세요.

      final uri = Uri.parse('$_backendBaseUrl/api/logs/filter').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> logs = json['data'];

        // 이전에 만든 배치 동기화 메서드 호출
        await AlarmStore.syncWithServer(logs.cast<Map<String, dynamic>>(), defaultName: _targetName);
        if (mounted) {
          setState(() {
            // 이 호출이 StreamBuilder를 다시 작동하게 트리거합니다.
            _stream = _alarmStream();
          });
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('네트워크 연결 대기 중... ($e)');
      return false;
    } finally {
      _isSyncing = false;
    }
  }

// 2. 스트림 루프에서 주기적으로 동기화 호출
  Stream<List<AlarmRecord>> _alarmStream() async* {
    int syncCounter = 0;

    while (mounted) {
      // 매 루프(1초)마다 로컬 DB를 읽어 화면에 즉시 반영
      List<AlarmRecord> allRecords = await AlarmStore.loadAllSortedDesc();

      if (_targetHost != null && _targetHost!.isNotEmpty) {
        yield allRecords.where((e) => e.host == _targetHost).toList();
      } else {
        yield allRecords;
      }

      // [자동 재시도] 10초마다 한 번씩 서버 동기화 시도
      // (네트워크가 끊겨있어도 10초마다 자동으로 재시도하게 됨)
      syncCounter++;
      if (syncCounter >= 10) {
        _syncWithServer();
        syncCounter = 0;
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
          backgroundColor: AppColor.bg,
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

          return RefreshIndicator(
            onRefresh: () async {
              // 당겨서 새로고침 시 서버 동기화 수행
              await _syncWithServer();

              // Stream은 자동으로 돌고 있지만 즉각 반영을 위해 setState
              if(mounted) {
                setState(() { _stream = _alarmStream(); });
              }
            },
            edgeOffset: 10,
            displacement: 10,
            color: Colors.white,
            backgroundColor: AppColor.duBlue,
            child: entries.isEmpty
                ? Stack(
              children: [
                ListView(), // ScrollView가 있어야 RefreshIndicator 동작함
                const Center(child: Text('알람 내역이 없습니다.', style: TextStyle(color: Colors.grey))),
              ],
            )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final e = entries[i];

                final occurredAt  = DateTime.fromMillisecondsSinceEpoch(e.tsMs, isUtc: true).toLocal();
                final occurredTxt = _formatKTime(occurredAt);

                final clearedAt   = (e.clearedTsMs != null)
                    ? DateTime.fromMillisecondsSinceEpoch(e.clearedTsMs!, isUtc: true).toLocal()
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