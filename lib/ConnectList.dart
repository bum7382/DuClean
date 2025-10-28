import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/modbus_manager.dart';
import '/routes.dart';
import 'res/Constants.dart';

// 연결 부분과 관련하여 처리되지 않았습니다.메뉴 프로토타입입니다. (미완성)

const String _kDevicesStoreKey = 'modbus_devices_v1';

class ConnectListPage extends StatefulWidget {
  const ConnectListPage({super.key});

  @override
  State<ConnectListPage> createState() => _ConnectListPageState();
}

class _ConnectListPageState extends State<ConnectListPage> {
  List<DeviceKey> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kDevicesStoreKey);

    if (raw == null || raw.isEmpty) {
      // 기본값 한 개
      _items = const [
        DeviceKey(host: '192.168.10.190', unitId: 1, name: 'AP-500'),
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
          if (host.isNotEmpty) {
            list.add(DeviceKey(host: host, unitId: unit, name: name));
          }
        } catch (_) {/* skip */}
      }
      if (list.isNotEmpty) _items = list;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final toSave = _items
        .map((e) => jsonEncode({'host': e.host, 'unitId': e.unitId, 'name': e.name}))
        .toList();
    await prefs.setStringList(_kDevicesStoreKey, toSave);
  }

  void _openMain(DeviceKey d) {
    Navigator.of(context).pushNamed(
      Routes.deviceMain,
      arguments: {'host': d.host, 'unitId': d.unitId, 'name': d.name},
    );
  }

  Future<void> _addDevice() async {
    final result = await showModalBottomSheet<DeviceKey>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DeviceEditSheet(),
    );
    if (result != null) {
      // 중복(host+unitId) 방지
      final exists = _items.any((e) => e.host == result.host && e.unitId == result.unitId);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('같은 Host/UnitID 장비가 이미 있습니다.')),
        );
        return;
      }
      setState(() => _items.add(result));
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
      // 다른 항목과의 중복 체크
      final exists = _items.asMap().entries.any((e) =>
      e.key != index && e.value.host == result.host && e.value.unitId == result.unitId);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('같은 Host/UnitID 장비가 이미 있습니다.')),
        );
        return;
      }
      setState(() => _items[index] = result);
      await _saveDevices();
    }
  }

  Future<void> _deleteDevice(int index) async {
    final d = _items[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('장비 삭제'),
        content: Text('${d.name} (${d.host} · Unit ${d.unitId})를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;

    // 연결 중이면 끊기
    await ModbusManager.instance.dispose(d);

    setState(() => _items.removeAt(index));
    await _saveDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기기 목록', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColor.duBlue,
        iconTheme: const IconThemeData(color: Colors.white),
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
              // 삭제 확인
              await _deleteDevice(i);
              return false; // 내부에서 삭제 처리했으므로 ListView가 중복 삭제하지 않게 false
            },
            child: _DeviceTile(
              device: d,
              onOpen: () => _openMain(d),
              onEdit: () => _editDevice(i),
              onDelete: () => _deleteDevice(i),
            ),
          );
        },
      ),
    );
  }
}

/// 단일 장비 타일 (연결 상태 구독 + 액션 버튼들)
class _DeviceTile extends StatefulWidget {
  const _DeviceTile({
    required this.device,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final DeviceKey device;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  bool _connected = false;
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    _connected = ModbusManager.instance.isConnected(widget.device);
    _connSub = ModbusManager.instance.connectionStream(widget.device)?.listen((v) {
      if (!mounted) return;
      setState(() => _connected = v);
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: _connected ? Colors.green : Colors.grey,
        child: const Icon(Icons.memory, color: Colors.white),
      ),
      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Text('${d.host}  ·  Unit ${d.unitId}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '수정',
            icon: const Icon(Icons.edit, color: Colors.grey),
            onPressed: widget.onEdit,
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.duBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: widget.onOpen,
            child: const Text('열기'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'disconnect') {
                await ModbusManager.instance.dispose(d);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('연결 해제됨')),
                );
              } else if (v == 'delete') {
                widget.onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'disconnect', child: Text('연결 해제')),
              PopupMenuItem(value: 'delete', child: Text('삭제')),
            ],
          ),
        ],
      ),
      onTap: widget.onOpen,
    );
  }
}

/// 추가/수정 공용 바텀시트
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Host는 필수입니다.')));
      return;
    }
    if (unit < 0 || unit > 247) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UnitID는 0~247 범위로 입력하세요.')));
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
                hintText: '예: AP-500',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host(IP 또는 도메인)',
                hintText: '예: 192.168.10.190',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Unit ID',
                hintText: '0 ~ 247',
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
