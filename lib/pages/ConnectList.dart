import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:duclean/services/modbus_manager.dart';
import 'package:duclean/services/routes.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/models/device_info.dart'; // DeviceKey, DeviceInfo 모델
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/services/motor_schedule_service.dart';
import 'package:duclean/services/wifi_finder_service.dart'; // 와이파이 스캔 서비스

const String _kDevicesStoreKey = 'modbus_devices_v1';

class ConnectListPage extends StatefulWidget {
  const ConnectListPage({super.key});

  @override
  State<ConnectListPage> createState() => _ConnectListPageState();
}

class _ConnectListPageState extends State<ConnectListPage> {
  List<DeviceKey> _items = [];
  bool _loading = true;
  bool _historyPollingStarted = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_historyPollingStarted) return;
    _historyPollingStarted = true;

    // 화면 빌드 후 폴링 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ModbusManager.instance.startHistoryPolling(context);
    });
  }

  @override
  void dispose() {
    ModbusManager.instance.stopHistoryPolling();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getStringList(_kDevicesStoreKey);

    if (raw == null || raw.isEmpty) {
      _items =  [];
    } else {
      final list = <DeviceKey>[];
      for (final s in raw) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          list.add(DeviceKey.fromJson(m));
        } catch (_) {/* skip */}
      }

      // 번호순 정렬
      list.sort((a, b) => (a.number == 0 ? 9999 : a.number).compareTo(b.number == 0 ? 9999 : b.number));

      // 번호 재할당 (MAC 주소 유지)
      if (list.isNotEmpty) {
        _items = list.asMap().entries.map((e) {
          final d = e.value;
          return DeviceKey(
            host: d.host,
            unitId: d.unitId,
            name: d.name,
            number: e.key + 1,
            macAddress: d.macAddress,
            serial: d.serial,
          );
        }).toList();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final toSave = _items.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_kDevicesStoreKey, toSave);
  }

  // [공통 로직] 기기 선택 및 스케줄 서비스 설정
  void _selectDeviceAndSetupService(DeviceKey d) {
    final dev = DeviceInfo(
      name: d.name,
      address: d.host,
      unitId: d.unitId,
      number: d.number,
      macAddress: d.macAddress, // MAC 주소 전달
      serial: d.serial,
    );

    context.read<SelectedDevice>().select(dev);

    MotorScheduleService().setSchedule(
      host: dev.address,
      unitId: dev.unitId,
      address: 0,
    );
  }

  // 설정 버튼 클릭
  void _openSetting(DeviceKey d) {
    _selectDeviceAndSetupService(d);
    Navigator.of(context).pushNamed(Routes.connectSettingPage);
  }

  // 메인(타일) 클릭
  void _openMain(DeviceKey d) {
    _selectDeviceAndSetupService(d);

    // 연결 상태 확인
    final isConnected = context
        .read<ConnectionRegistry>()
        .stateOf(d.host, d.unitId)
        .connected;

    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('기기에 연결되어 있지 않습니다. 설정에서 연결 후 접속하세요.')),
      );
      Navigator.of(context).pushNamed(Routes.connectSettingPage);
    } else {
      Navigator.of(context).pushNamed(Routes.mainPage);
    }
  }

  // 기기 추가
  Future<void> _addDevice() async {
    final result = await showModalBottomSheet<DeviceKey>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _DeviceEditSheet(),
    );
    if (result != null) {
      final exists = _items.any((e) => e.host == result.host && e.unitId == result.unitId);
      if (exists) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('같은 Host/UnitID 장비가 이미 있습니다.')));
        return;
      }

      int maxNo = 0;
      for (final e in _items) {
        if (e.number > maxNo) maxNo = e.number;
      }

      setState(() {
        _items.add(DeviceKey(
          host: result.host,
          unitId: result.unitId,
          name: result.name,
          number: maxNo + 1,
          macAddress: result.macAddress,
          serial: result.serial
        ));
      });
      await _saveDevices();
      await _loadDevices();
    }


  }

  // 기기 수정
  Future<void> _editDevice(int index) async {
    final d = _items[index];
    final result = await showModalBottomSheet<DeviceKey>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DeviceEditSheet(initial: d),
    );
    if (result != null) {
      final exists = _items.asMap().entries.any(
            (e) => e.key != index && e.value.host == result.host && e.value.unitId == result.unitId,
      );
      if (exists) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('같은 Host/UnitID 장비가 이미 있습니다.')));
        return;
      }

      final old = _items[index];
      setState(() {
        _items[index] = DeviceKey(
          host: result.host,
          unitId: result.unitId,
          name: result.name,
          number: old.number,
          macAddress: result.macAddress,
          serial: result.serial
        );
      });
      await _saveDevices();
    }
  }

  // 기기 삭제
  Future<void> _deleteDevice(int index) async {
    final d = _items[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('장비 삭제'),
        content: Text('${d.name} (${d.host})를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;

    await ModbusManager.instance.disconnect(context, host: d.host, unitId: d.unitId);

    setState(() {
      _items.removeAt(index);
      // 순번 재정렬
      _items = _items.asMap().entries.map((e) {
        return DeviceKey(
          host: e.value.host,
          unitId: e.value.unitId,
          name: e.value.name,
          number: e.key + 1,
          macAddress: e.value.macAddress,
          serial: e.value.serial
        );
      }).toList();
    });
    await _saveDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        centerTitle: false,
        title: const Text('기기 목록', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pushNamedAndRemoveUntil(
            Routes.introPage, // 인트로 경로
              (route) => false, // 기존의 모든 스택 제거
            );
          }
        ),
        backgroundColor: AppColor.duBlue,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDevice,
        backgroundColor: AppColor.duBlue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const Center(child: Text('등록된 장비가 없습니다. + 버튼으로 추가하세요.'))
          : ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final d = _items[i];
          return Dismissible(
            key: ValueKey('${d.host}#${d.unitId}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) async {
              await _deleteDevice(i);
              return false;
            },
            child: _DeviceTile(
              device: d,
              number: d.number,
              onOpen: () => _openMain(d),
              onSetting: () => _openSetting(d),
              onEdit: () => _editDevice(i),
              onDelete: () => _deleteDevice(i),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 아래부분이 DeviceTile (리스트 아이템 UI)
// ---------------------------------------------------------------------------

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.number,
    required this.onOpen,
    required this.onSetting,
    required this.onEdit,
    required this.onDelete,
  });

  final DeviceKey device;
  final int number;
  final VoidCallback onOpen;
  final VoidCallback onSetting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    final d = device;

    // 연결 상태 구독 (Registry에서 상태 확인)
    final connected = context.select<ConnectionRegistry, bool>(
          (r) => r.stateOf(d.host, d.unitId).connected,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      leading: Stack(
        children: [
          Image.asset(
            connected ? "assets/images/logo_color.png" : "assets/images/logo_black.png",
            width: w * 0.1,
          ),
          Positioned(
            child: Text(
              number.toString(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: connected ? AppColor.duBlue : Colors.black,
              ),
            ),
          ),
        ],
      ),
      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 10)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IP: ${d.host}', style: const TextStyle(fontWeight: FontWeight.w200, fontSize: 9)),
          Text('Unit ID: ${d.unitId}', style: const TextStyle(fontWeight: FontWeight.w200, fontSize: 9)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit, color: AppColor.duGrey),
            onPressed: onEdit,
            visualDensity: const VisualDensity(horizontal: -3.5),
          ),
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings, color: AppColor.duGrey),
            onPressed: onSetting,
            visualDensity: const VisualDensity(horizontal: -3.5),
          ),
          PopupMenuButton<String>(
            iconColor: AppColor.duGrey,
            color: AppColor.bg,
            onSelected: (v) async {
              if (v == 'disconnect') {
                await ModbusManager.instance.disconnect(context, host: d.host, unitId: d.unitId);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연결 해제됨')));
              } else if (v == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'disconnect', child: Text('연결 해제')),
              PopupMenuItem(value: 'delete', child: Text('삭제')),
            ],
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}

// ---------------------------------------------------------------------------
// 기기 추가/수정 바텀시트 (와이파이 스캔 포함)
// ---------------------------------------------------------------------------

class _DeviceEditSheet extends StatefulWidget {
  const _DeviceEditSheet({this.initial});
  final DeviceKey? initial;

  @override
  State<_DeviceEditSheet> createState() => _DeviceEditSheetState();
}

class _DeviceEditSheetState extends State<_DeviceEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _unit;
  late final TextEditingController _mac;
  late final TextEditingController _serial;

  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _host = TextEditingController(text: widget.initial?.host ?? '');
    _unit = TextEditingController(text: widget.initial?.unitId.toString() ?? '1');
    _mac = TextEditingController(text: widget.initial?.macAddress ?? '');
    _serial = TextEditingController(text: widget.initial?.serial ?? '');
  }

  // 서버로 시리얼 매칭 정보를 보내는 함수
  Future<void> _syncSerialWithBackend(String mac, String serial) async {
    final String apiUrl = dotenv.env['API_URL'] ?? ""; // .env의 API_URL

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/serial'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mac': mac,
          'serial': serial,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint('✅ 서버 매칭 성공');
      } else {
        debugPrint('❌ 서버 에러: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ 통신 실패: $e');
    }
  }

  // 서버에서 해당 MAC의 시리얼 번호를 가져와서 입력창에 채우는 함수
  Future<void> _fetchAndApplySerial(String mac) async {
    final String apiUrl = dotenv.env['API_URL'] ?? "";
    if (apiUrl.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('$apiUrl/api/serial/$mac'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final String foundSerial = data['serial'];
          setState(() {
            _serial.text = foundSerial; // 시리얼 번호 자동 입력
          });
          debugPrint('✅ DB에서 시리얼 조회 성공: $foundSerial');
        }
      }
    } catch (e) {
      debugPrint('❌ 시리얼 조회 에러: $e');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _unit.dispose();
    _mac.dispose();
    _serial.dispose();
    super.dispose();
  }

  // 와이파이 스캔 로직
  Future<void> _scanDevice() async {
    if (!Platform.isAndroid) return;

    setState(() => _isScanning = true);

    // 1. 리스트 받아오기
    final List<String> foundList = await WifiFinderService().scanAndGetList();

    if (!mounted) return;
    setState(() => _isScanning = false);

    // 2. 결과에 따른 처리
    if (foundList.isEmpty) {
      // Case A: 없음
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DUCLEAN의 IoT 기기를 찾을 수 없습니다.')),
      );
    }
    else if (foundList.length == 1) {
      // Case B: 딱 1개 발견 -> 자동 입력
      final mac = foundList.first;
      _mac.text = 'DUCLEAN_$mac';
      _fetchAndApplySerial(mac);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('기기 발견! ($mac)')),
      );
    }
    else {
      // Case C: 여러 개 발견 -> 사용자 선택 팝업 띄우기
      _showSelectionDialog(foundList);
    }
  }



  void _showSelectionDialog(List<String> macList) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('IoT 기기를 선택해주세요.', style: TextStyle(fontSize: 20),),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: macList.length,
              itemBuilder: (context, index) {
                final mac = macList[index];
                return ListTile(
                  title: Text("DUCLEAN_$mac", style: TextStyle(fontSize: 13),), // 전체 이름 보여주기
                  leading: const Icon(Icons.wifi, color: AppColor.duBlue),
                  onTap: () {
                    // 선택 시 텍스트 채우고 닫기
                    setState(() {
                      _mac.text = 'DUCLEAN_$mac';
                      //_mac.text = '$mac';
                    });
                    _fetchAndApplySerial(mac);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('선택 완료: $mac')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소', style: TextStyle(color: AppColor.duBlue),),
            ),
          ],
        );
      },
    );
  }

  // 경고창
  void _showWarning(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('입력 확인'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인', style: TextStyle(color: AppColor.duBlue),),
          ),
        ],
      ),
    );
  }

  void _submit() async {
    final name = _name.text.trim().isEmpty ? 'Device' : _name.text.trim();
    final host = _host.text.trim();
    final unit = int.tryParse(_unit.text.trim()) ?? -1;
    final serial = _serial.text.trim();
    String errorMessage = '';
    String rawMacInput = _mac.text.trim();
    String mac = rawMacInput;

    if (rawMacInput.startsWith('DUCLEAN_')) {
      mac = rawMacInput.substring(8); // 앞 8글자 제거
    }

    if (host.isEmpty) {
      errorMessage += 'IP 주소를 입력해 주세요. ';
    }

    if (unit < 0 || unit > 247) {
      errorMessage += 'UnitID는 0~247 범위여야 합니다. ';
    }

    if (mac.isEmpty) {
      errorMessage += 'IoT 기기 정보가 없습니다. 스캔 버튼을 눌러주세요. ';
    }

    if (serial.isEmpty) {
      errorMessage += '시리얼 번호를 입력해주세요.';
    }

    if(errorMessage != '') {
      _showWarning(errorMessage);
      return;
    }

    // 서버에 매칭 정보 전송
    await _syncSerialWithBackend(mac, serial);

    Navigator.pop(context, DeviceKey(
      host: host,
      unitId: unit,
      name: name,
      number: 0,
      macAddress: mac,
      serial: serial
    ));
  }

  @override
  Widget build(BuildContext context) {

    final isEdit = widget.initial != null;
    final insets = MediaQuery.of(context).viewInsets;

    final isAndroid = Platform.isAndroid;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isEdit ? '장비 수정' : '장비 추가', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                // 스캔 버튼
                if (isAndroid)
                  TextButton.icon(
                    onPressed: _isScanning ? null : _scanDevice,
                    icon: _isScanning
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find, color: AppColor.duBlue),
                    label: Text(_isScanning ? '스캔 중...' : 'IoT 기기 스캔', style: const TextStyle(color: AppColor.duBlue)),
                  )
                else
                // iOS일 때 보여줄 문구
                  const Text(
                    "iOS는 직접 입력해주세요",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // MAC 주소 표시 (읽기 전용)
            TextField(
              controller: _mac,
              readOnly: isAndroid && _isScanning,
              decoration: InputDecoration(
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2.0),
                ),
                labelText: isAndroid ? 'IoT 기기 정보 [MAC]' : '기기 정보 (직접 입력)',
                border: OutlineInputBorder(),
                hintText: isAndroid ? null : '예: DUCLEAN_AABBCC',
                filled: true,
                fillColor: Colors.transparent,
                labelStyle: TextStyle(color: AppColor.duBlack),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: InputDecoration(
                labelText: 'IP 주소',
                hintText: '192.168.x.x',
                border: OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2.0),
                ),
                labelStyle: TextStyle(color: AppColor.duBlack),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Unit ID',
                border: OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2.0),
                ),
                labelStyle: TextStyle(color: AppColor.duBlack),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2.0),
                ),
                labelStyle: TextStyle(color: AppColor.duBlack),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serial,
              decoration: const InputDecoration(
                labelText: '기기 시리얼 번호',
                hintText: '기기에 부착된 시리얼 번호 입력',
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColor.duBlue, width: 2.0),
                ),
                labelStyle: TextStyle(color: AppColor.duBlack),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: AppColor.duBlue),))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(backgroundColor: AppColor.duBlue),
                    child: Text(isEdit ? '저장' : '추가')
                )),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}