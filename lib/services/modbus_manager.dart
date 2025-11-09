// lib/services/modbus_manager.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:provider/provider.dart';
import '../providers/selected_device.dart'; // ConnectionRegistry

class ModbusManager {
  ModbusManager._();
  static final ModbusManager instance = ModbusManager._();

  final Map<String, ModbusClientTcp> _clients = {}; // key: host#unitId
  String _key(String host, int unitId) => '$host#$unitId';

  Future<ModbusClientTcp?> _connect(String host, int unitId) async {
    final c = ModbusClientTcp(host, unitId: unitId);
    await c.connect(); // TCP 소켓 연결
    return c;
  }

  // ✅ 헬스 체크: Holding Register #1 한 번 읽어서 슬레이브 응답 확인
  Future<bool> _ping(ModbusClientTcp c, {int address = 1, Duration timeout = const Duration(milliseconds: 600)}) async {
    final reg = ModbusInt16Register(
      name: 'ping($address)',
      type: ModbusElementType.holdingRegister, // FC03
      address: address,
    );
    try {
      await c.send(reg.getReadRequest()).timeout(timeout);
      return reg.value != null; // 값 도착해야 OK
    } catch (_) {
      return false;
    }
  }

  /// 🔗 연결 보장 + 헬스 체크. 슬레이브 응답까지 확인된 경우에만 connected로 마킹
  Future<ModbusClientTcp> ensureConnected(
      BuildContext context, {
        required String host,
        required int unitId,
        int verifyAddress = 1, // 기본: #1 읽기
      }) async {
    final k = _key(host, unitId);

    // 1) 재사용 가능한 기존 소켓이 있으면 먼저 핑으로 검증
    final cur = _clients[k];
    if (cur != null && cur.isConnected) {
      final ok = await _ping(cur, address: verifyAddress);
      if (ok) {
        context.read<ConnectionRegistry>().markConnected(host, unitId);
        return cur;
      } else {
        // 끊고 새로 시도
        try { await cur.disconnect(); } catch (_) {}
        _clients.remove(k);
        context.read<ConnectionRegistry>().markDisconnected(host, unitId);
      }
    }

    // 2) 새로 연결
    final nc = await _connect(host, unitId);

    // 3) 헬스 체크 통과 시에만 connected 표시
    final healthy = await _ping(nc!, address: verifyAddress);
    if (healthy) {
      _clients[k] = nc;
      context.read<ConnectionRegistry>().markConnected(host, unitId);
      return nc;
    } else {
      // 응답 없음 → 정리 후 예외
      try { await nc.disconnect(); } catch (_) {}
      _clients.remove(k);
      context.read<ConnectionRegistry>().markDisconnected(host, unitId);
      throw Exception('Modbus slave not responding (host=$host, unitId=$unitId)');
    }
  }

  Future<void> disconnect(BuildContext context, {required String host, required int unitId}) async {
    final k = _key(host, unitId);
    try { await _clients[k]?.disconnect(); } catch (_) {}
    _clients.remove(k);
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
