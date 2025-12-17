import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http; // [추가] 패키지 import
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
  String? _targetMac;
  bool _isInit = false;

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
  Future<void> _syncWithServer() async {
    // 호스트나 맥 주소가 없으면 불필요한 호출 방지 (필요 시 주석 해제하여 전체 호출 가능)
    if (_targetHost == null && _targetMac == null) return;

    try {
      final Map<String, String> queryParams = {};
      if (_targetHost != null) queryParams['ip'] = _targetHost!;
      if (_targetMac != null) queryParams['mac'] = _targetMac!;

      // 쿼리 파라미터가 비어있으면 active=true를 넣어 400 에러 방지
      if (queryParams.isEmpty) queryParams['active'] = 'true';

      final uri = Uri.parse('$_backendBaseUrl/api/logs/filter')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> logs = json['data'];

        for (var log in logs) {
          final String ip = log['ip_address'] ?? '';
          final int code = (log['code'] != null) ? int.parse(log['code'].toString()) : 0;
          final bool isActive = log['active'] == true || log['active'].toString() == 'true';

          final DateTime dt = DateTime.parse(log['timestamp']);
          final int tsMs = dt.millisecondsSinceEpoch;

          // 표시 이름 설정
          final String displayName = _targetName ?? log['mac_address'] ?? 'Unknown';

          if (isActive) {
            // 발생 내역 저장 (중복 체크는 AlarmStore 내부에서 처리)
            await AlarmStore.appendOccurrence(
              host: ip,
              unitId: 1, // 기본값
              name: displayName,
              code: code,
              tsMs: tsMs,
            );
          } else {
            // 해제 내역 처리 (기존 알람 업데이트)
            await AlarmStore.appendClear(
              host: ip,
              unitId: 1, // 기본값
              code: code,
              clearedAtMs: tsMs,
            );
          }
        }
        debugPrint('백엔드 동기화 완료: ${logs.length}건');
      }
    } catch (e) {
      debugPrint('서버 동기화 실패: $e');
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
          // if (entries.isEmpty) {
          //   // 빈 화면이라도 당겨서 새로고침 할 수 있게 아래로 이동
          // }

          return RefreshIndicator(
            onRefresh: () async {
              // [수정] 당겨서 새로고침 시 서버 동기화 수행
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