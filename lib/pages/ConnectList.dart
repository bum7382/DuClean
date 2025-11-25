import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'package:duclean/services/modbus_manager.dart';
import 'package:duclean/services/routes.dart';
import 'package:duclean/res/Constants.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/models/device_info.dart';
import 'package:duclean/common/context_extensions.dart';
import 'package:duclean/services/motor_schedule_service.dart';

const String _kDevicesStoreKey = 'modbus_devices_v1';

class ConnectListPage extends StatefulWidget {
  const ConnectListPage({super.key});

  @override
  State<ConnectListPage> createState() => _ConnectListPageState();
}

class _ConnectListPageState extends State<ConnectListPage> {
  List<DeviceKey> _items = []; // 저장된 기기
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

    // 첫 프레임 빌드가 끝난 뒤에 폴링 시작 (context 안정화)
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
    final raw = prefs.getStringList(_kDevicesStoreKey);

    if (raw == null || raw.isEmpty) {
      _items = const [
        DeviceKey(host: '192.168.10.190', unitId: 1, name: 'AP-500', number: 1),
      ];
      await _saveDevices();
    } else {
      final list = <DeviceKey>[];
      for (final s in raw) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final host = (m['host'] as String?) ?? '';
          final unit = (m['unitId'] as num?)?.toInt() ?? 1;
          final name = (m['name'] as String?) ?? 'Device';
          final numVal = (m['number'] as num?)?.toInt();
          if (host.isNotEmpty) {
            final tempNumber = numVal ?? 0;
            list.add(DeviceKey(host: host, unitId: unit, name: name, number: tempNumber));
          }
        } catch (_) {/* skip */}
      }

      list.sort((a, b) => (a.number == 0 ? 9999 : a.number).compareTo(b.number == 0 ? 9999 : b.number));

      // 리스트 순서대로 number를 1부터 재할당
      if (list.isNotEmpty) {
        _items = list.asMap().entries.map((e) {
          final d = e.value;
          return DeviceKey(
            host: d.host,
            unitId: d.unitId,
            name: d.name,
            number: e.key + 1,
          );
        }).toList();
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final toSave = _items
        .map((e) => jsonEncode({'host': e.host, 'unitId': e.unitId, 'name': e.name, 'number': e.number}))
        .toList();
    await prefs.setStringList(_kDevicesStoreKey, toSave);
  }

  // 설정: 선택 저장 → 설정 페이지로 이동

  void _openSetting(DeviceKey d) {
    // 1) 선택 기기 설정
    final dev = DeviceInfo(
      name: d.name,
      address: d.host,
      unitId: d.unitId,
      number: d.number,
    );
    context.read<SelectedDevice>().select(dev);

    // 2) 스케줄 대상 기기 설정
    MotorScheduleService().setSchedule(
      host: dev.address,
      unitId: dev.unitId,
      address: 0,
    );

    // 3) 설정 화면으로 이동
    Navigator.of(context).pushNamed(Routes.connectSettingPage);
  }


// 메인: 선택 → 연결 여부 확인(Registry 기준) → 이동
  void _openMain(DeviceKey d) {
    // 1) 선택 기기 설정
    final dev = DeviceInfo(
      name: d.name,
      address: d.host,
      unitId: d.unitId,
      number: d.number,
    );
    context.read<SelectedDevice>().select(dev);

    // 2) 스케줄 대상 기기 설정
    MotorScheduleService().setSchedule(
      host: dev.address,
      unitId: dev.unitId,
      address: 0,
    );

    // 3) 연결 여부 확인
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('같은 Host/UnitID 장비가 이미 있습니다.')));
        return;
      }

      int maxNo = 0;
      for (final e in _items) {
        if (e.number > maxNo) maxNo = e.number;
      }
      final nextNo = maxNo + 1;

      setState(() {
        _items.add(
          DeviceKey(
            host: result.host,
            unitId: result.unitId,
            name: result.name,
            number: nextNo,
          ),
        );
      });
      await _saveDevices();
    }
  }

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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('같은 Host/UnitID 장비가 이미 있습니다.')));
        return;
      }

      final old = _items[index];

      setState(() {
        _items[index] = DeviceKey(
          host: result.host,
          unitId: result.unitId,
          name: result.name,
          number: old.number,
        );
      });
      await _saveDevices();
    }
  }

  Future<void> _deleteDevice(int index) async {
    final d = _items[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('장비 삭제'),
        content: Text('${d.name} (${d.host} | Unit ${d.unitId})를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;

    // 연결되어 있었다면 끊고 레지스트리 갱신까지 내부에서 처리
    await ModbusManager.instance.disconnect(context, host: d.host, unitId: d.unitId);

    setState(() {
      // 해당 항목 삭제
      _items.removeAt(index);

      // 순서 재할당
      _items = _items.asMap().entries.map((e) {
        final currentIdx = e.key;
        final oldDevice = e.value;

        return DeviceKey(
          host: oldDevice.host,
          unitId: oldDevice.unitId,
          name: oldDevice.name,
          number: currentIdx + 1,
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
        title: const Text(
          '기기 목록',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
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
          final no = (d.number != 0) ? d.number : (i + 1);
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
              number: no,
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

/// 단일 장비 타일 (Registry 구독으로 연결상태 표시)
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

    // connected 값만 구독(리빌드 최소화)
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
         //기기 목록 순번
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
        ]
      ),
      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 10)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IP: ${d.host}',
            style: const TextStyle(fontWeight: FontWeight.w200, fontSize: 9),
          ),
          Text('Unit ID : ${d.unitId}',
            style: const TextStyle(fontWeight: FontWeight.w200, fontSize: 9),
          ),
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
            //visualDensity: VisualDensity.compact,
              visualDensity: const VisualDensity(horizontal: -3.5)
          ),
          PopupMenuButton<String>(
            iconColor: AppColor.duGrey,
            onSelected: (v) async {
              if (v == 'disconnect') {
                await ModbusManager.instance.disconnect(context, host: d.host, unitId: d.unitId);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('연결 해제됨')));
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

/// 추가/수정 바텀시트
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

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _host = TextEditingController(text: widget.initial?.host ?? '');
    _unit = TextEditingController(text: widget.initial?.unitId.toString() ?? '1');
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim().isEmpty ? 'Device' : _name.text.trim();
    final host = _host.text.trim();
    final unit = int.tryParse(_unit.text.trim()) ?? 1;

    if (host.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Host는 필수입니다.')));
      return;
    }
    if (unit < 0 || unit > 247) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('UnitID는 0~247 범위로 입력하세요.')));
      return;
    }

    Navigator.pop(context, DeviceKey(host: host, unitId: unit, name: name));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isEdit ? '장비 수정' : '장비 추가',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: 'AP-500',
                hintStyle: TextStyle(color: Colors.black26),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'IP',
                hintText: '예: 192.168.10.190',
                hintStyle: TextStyle(color: Colors.black26),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Unit ID',
                hintText: '0',
                hintStyle: TextStyle(color: Colors.black26),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(backgroundColor: AppColor.duBlue),
                    child: Text(isEdit ? '저장' : '추가'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
