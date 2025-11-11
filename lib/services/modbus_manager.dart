// lib/services/modbus_manager.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/services/alarm_store.dart';

class ModbusManager {
  ModbusManager._();
  static final ModbusManager instance = ModbusManager._();

  final Map<String, ModbusClientTcp> _clients = {}; // key: host#unitId
  final Map<String, _AlarmPoller> _alarmPollers = {};
  String _key(String host, int unitId) => '$host#$unitId';

  Future<ModbusClientTcp?> _connect(String host, int unitId) async {
    final c = ModbusClientTcp(host, unitId: unitId);
    await c.connect(); // TCP 소켓 연결
    return c;
  }

  void _autoStartAlarmWatch(String host, int unitId) {
    final k = _key(host, unitId);
    if (_alarmPollers.containsKey(k)) return; // 이미 감시 중
    final poller = _AlarmPoller(
      host: host,
      unitId: unitId,
      name: '$host#$unitId', // 표시명(필요하면 아래 3-참고의 setDeviceLabel로 나중에 교체 가능)
      interval: const Duration(seconds: 1),
      ensure: ({int verifyAddress = 0}) =>
          ensureConnectedSilent(host: host, unitId: unitId, verifyAddress: verifyAddress),
    );
    _alarmPollers[k] = poller;
    poller.start();
  }

  // 헬스 체크: Holding Register #1 한 번 읽어서 슬레이브 응답 확인
  Future<bool> _ping(ModbusClientTcp c, {int address = 0, Duration timeout = const Duration(seconds: 2)}) async {
    final reg = ModbusUint16Register(
      name: 'ping_in($address)',
      type: ModbusElementType.inputRegister, // FC04
      address: address,
    );
    try {
      await c.send(reg.getReadRequest()).timeout(timeout);
      return reg.value != null;
    } catch (_) {
      return false;
    }
  }

  /// 🔗 연결 보장 + 헬스 체크. 슬레이브 응답까지 확인된 경우에만 connected로 마킹
  Future<ModbusClientTcp> ensureConnected(
      BuildContext context, {
        required String host,
        required int unitId,
        int verifyAddress = 0, // 기본: 입력레지스터 #0
      })
  async {
    final k = _key(host, unitId);

    // 1) 재사용: 기존 소켓이 있고 연결 상태면 그대로 사용(매 틱 핑 제거)
    final cur = _clients[k];
    if (cur != null && cur.isConnected) {
      context.read<ConnectionRegistry>().markConnected(host, unitId);
      _autoStartAlarmWatch(host, unitId);
      return cur;
    }

    // 2) 새로 연결
    final nc = await _connect(host, unitId);

    // 3) 최초 연결 시에만 핑
    final healthy = await _ping(nc!, address: verifyAddress);
    if (healthy) {
      _clients[k] = nc;
      context.read<ConnectionRegistry>().markConnected(host, unitId);
      _autoStartAlarmWatch(host, unitId);
      return nc;
    } else {
      try { await nc.disconnect(); } catch (_) {}
      _clients.remove(k);
      context.read<ConnectionRegistry>().markDisconnected(host, unitId);
      throw Exception('Modbus slave not responding (host=$host, unitId=$unitId)');
    }
  }

  /// 컨텍스트 없이 조용히 연결 보장(Provider 갱신/markConnected 생략)
  Future<ModbusClientTcp> ensureConnectedSilent({
    required String host,
    required int unitId,
    int verifyAddress = 0, // 입력레지스터 #0 권장
  }) async {
    final k = _key(host, unitId);

    // 재사용
    final cur = _clients[k];
    if (cur != null && cur.isConnected) {
      _autoStartAlarmWatch(host, unitId);
      return cur;
    }

    // 새 연결
    final nc = await _connect(host, unitId);

    // 최초 연결만 가벼운 핑(입력레지스터 #0)
    final healthy = await _ping(nc!, address: verifyAddress);
    if (healthy) {
      _clients[k] = nc;
      _autoStartAlarmWatch(host, unitId);
      return nc;
    } else {
      try { await nc.disconnect(); } catch (_) {}
      _clients.remove(k);
      throw Exception('Modbus slave not responding (host=$host, unitId=$unitId)');
    }
  }

  /// 전역 알람 감시 시작(이미 있으면 무시)
  void startAlarmWatch({
    required String host,
    required int unitId,
    required String name, // 표시용 기기명
    Duration interval = const Duration(seconds: 1),
  }) {
    final k = _key(host, unitId);
    if (_alarmPollers.containsKey(k)) return;

    final poller = _AlarmPoller(
      host: host,
      unitId: unitId,
      name: '$host#$unitId',
      interval: interval,
      ensure: ({int verifyAddress = 0}) =>
          ensureConnectedSilent(host: host, unitId: unitId, verifyAddress: verifyAddress),
    );
    _alarmPollers[k] = poller;
    poller.start();
  }

  /// 전역 알람 감시 중지(타이머만 중지; 소켓은 그대로 둠)
  void stopAlarmWatch(String host, int unitId) {
    final k = _key(host, unitId);
    _alarmPollers.remove(k)?.stop();
  }

  /// 감시자가 없으면 연결을 끊어도 되는 경우에만 끊기
  Future<void> maybeDisconnect(BuildContext context, {required String host, required int unitId}) async {
    final k = _key(host, unitId);
    if (_alarmPollers.containsKey(k)) return; // 감시 중이면 유지
    await disconnect(context, host: host, unitId: unitId);
  }



  Future<void> disconnect(BuildContext context, {required String host, required int unitId}) async {
    final k = _key(host, unitId);
    try { await _clients[k]?.disconnect(); } catch (_) {}
    _clients.remove(k);
    _alarmPollers.remove(k)?.stop();
    context.read<ConnectionRegistry>().markDisconnected(host, unitId);
  }

  Future<int?> readHolding(
      BuildContext context, {
        required String host,
        required int unitId,
        required int address,
      }) async {
    final c = await ensureConnected(context, host: host, unitId: unitId);
    final reg = ModbusInt16Register(
      name: "Holding($address)",
      type: ModbusElementType.holdingRegister, // FC03
      address: address,
    );
    await c.send(reg.getReadRequest());
    return reg.value?.toInt();
  }

  Future<bool> writeHolding(
      BuildContext context, {
        required String host,
        required int unitId,
        required int address,
        required int value,
      }) async {
    final c = await ensureConnected(context, host: host, unitId: unitId);
    final reg = ModbusInt16Register(
      name: "Holding($address)",
      type: ModbusElementType.holdingRegister, // FC06
      address: address,
    );
    await c.send(reg.getWriteRequest(value));
    return true;
  }
}

class _AlarmPoller {
  _AlarmPoller({
    required this.host,
    required this.unitId,
    required this.name,
    required this.interval,
    required this.ensure,
  });

  final String host;
  final int unitId;
  final String name;
  final Duration interval;
  final Future<ModbusClientTcp> Function({int verifyAddress}) ensure;

  Timer? _t;
  int _lastCode = -1; // 미정 상태

  void start() {
    _t?.cancel();
    _t = Timer.periodic(interval, (_) async {
      try {
        final c = await ensure(verifyAddress: 0);

        // 입력레지스터 #25: 알람 코드
        final reg = ModbusUint16Register(
          name: 'in_25',
          type: ModbusElementType.inputRegister, // FC04
          address: 25,
        );
        await c.send(reg.getReadRequest());
        final cur = reg.value?.toInt() ?? 0;

        if (_lastCode == -1) {
          _lastCode = cur;
          return;
        }

        if (_lastCode != cur) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (cur > 0) {
            // 알람 발생
            await AlarmStore.appendOccurrence(
              host: host, unitId: unitId, name: name,
              code: cur, tsMs: nowMs,
            );
          } else if (_lastCode > 0) {
            // 알람 해제
            await AlarmStore.appendClear(
              host: host, unitId: unitId, code: _lastCode, clearedAtMs: nowMs,
            );
          }
          _lastCode = cur;
        }
      } catch (_) {
        // 통신 실패는 조용히 무시(다음 틱 재시도)
      }
    });
  }

  void stop() {
    _t?.cancel();
    _t = null;
  }
}

