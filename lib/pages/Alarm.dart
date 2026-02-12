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

  // 필터 및 기간 상태 변수
  int? _selectedCode; // null이면 전체
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);

  // 필터 목록 정의
  final List<Map<String, dynamic>> _filters = [
    {'code': null, 'label': '전체'},
    {'code': 1, 'label': '과전류'},
    {'code': 2, 'label': '운전에러'},
    {'code': 3, 'label': '모터 역방향'},
    {'code': 4, 'label': '전류 불평형'},
    {'code': 5, 'label': '과차압'},
    {'code': 6, 'label': '필터교체'},
    {'code': 7, 'label': '저차압'},
  ];

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


// 서버 동기화 함수
  Future<bool> _syncWithServer() async {
    if (_targetHost == null && _targetMac == null) return false;
    if (_isSyncing) return false; // 이미 동기화 중이면 중복 실행 방지

    _isSyncing = true;
    try {
      final Map<String, String> queryParams = {
        'start': _startDate.toIso8601String(),
        'end': _endDate.toIso8601String(),
      };
      if (_targetHost != null) queryParams['ip'] = _targetHost!;
      if (_targetMac != null) queryParams['mac'] = _targetMac!;

      final uri = Uri.parse('$_backendBaseUrl/api/logs/filter').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> logs = json['data'];
        await AlarmStore.syncWithServer(logs.cast<Map<String, dynamic>>(), defaultName: _targetName);
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

// 동기화 호출
  Stream<List<AlarmRecord>> _alarmStream() async* {
    while (mounted) {
      List<AlarmRecord> allRecords = await AlarmStore.loadAllSortedDesc();

      // 1. 기기 필터링
      if (_targetHost != null && _targetHost!.isNotEmpty) {
        allRecords = allRecords.where((e) => e.host == _targetHost).toList();
      }

      // 2. 알람 종류 필터링
      if (_selectedCode != null) {
        allRecords = allRecords.where((e) => e.code == _selectedCode).toList();
      }

      // 3. 기간 필터링
      allRecords = allRecords.where((e) {
        final dt = DateTime.fromMillisecondsSinceEpoch(e.tsMs);
        return dt.isAfter(_startDate) && dt.isBefore(_endDate);
      }).toList();

      yield allRecords;
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  // 기간 선택 팝업
  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            // 전체적인 테마 색상 설정
            colorScheme: ColorScheme.light(
              primary: AppColor.duBlue,
              onPrimary: Colors.white,
              secondary: AppColor.duBlue,
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
              primaryContainer: AppColor.duBlue.withValues(alpha: 0.1),
              onPrimaryContainer: AppColor.duBlue,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColor.duBlue,
              foregroundColor: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColor.duBlue,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0);
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        _stream = _alarmStream();
      });
      _syncWithServer();
    }
  }

  // 상단 필터 위젯
  Widget _buildFilterBar() {
    return Container(
      height: 50,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _selectedCode == filter['code'];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(filter['label']),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCode = filter['code'];
                  _stream = _alarmStream();
                });
              },
              selectedColor: AppColor.duBlue.withAlpha(40),
              labelStyle: TextStyle(
                color: isSelected ? AppColor.duBlue : Colors.black54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              backgroundColor: Colors.grey[100],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
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

    // 기기 선택 여부에 따라 삭제 로직 분기
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
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white), // 필터/날짜 아이콘
            onPressed: _showDateRangePicker,
          ),
        ],
        backgroundColor: AppColor.duBlue,
      ),
      body:
        Column(
          children: [
            _buildFilterBar(), // 상단 필터 바 추가
            const Divider(height: 1, thickness: 0.5),
            Expanded(
            child: StreamBuilder<List<AlarmRecord>>(
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
                  ),
          ],
        ),
    );
  }
}