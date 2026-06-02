// lib/services/modbus_manager.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:provider/provider.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/services/alarm_store.dart';
import 'package:duclean/providers/selected_device.dart';
import 'package:duclean/providers/dp_history.dart';
import 'package:duclean/providers/power_history.dart';

class ModbusManager {
  ModbusManager._();
  static final ModbusManager instance = ModbusManager._();

  final Map<String, ModbusClientTcp> _clients = {}; // key: host#unitId
  final Map<String, _AlarmPoller> _alarmPollers = {};

  // 같은 TCP 클라이언트(=같은 host#unitId)로 가는 send 호출을 직렬화하기 위한 FIFO 큐.
  // 동시에 두 곳에서 readHoldingRange 등을 호출해도 응답이 섞이지 않도록 보호한다.
  final Map<String, Future<void>> _sendTail = {};

  Future<T> _withClientLock<T>(String key, Future<T> Function() body) {
    final prev = _sendTail[key];
    final next = Completer<void>();
    _sendTail[key] = next.future;
    return Future.sync(() async {
      if (prev != null) {
        try { await prev; } catch (_) {}
      }
      try {
        return await body();
      } finally {
        next.complete();
        if (_sendTail[key] == next.future) {
          _sendTail.remove(key);
        }
      }
    });
  }

  /// 외부에서 같은 host#unitId 의 client 작업을 직렬화하고 싶을 때 호출.
  /// (예: Main.dart 의 직접 c.send() 호출처럼 ModbusManager 외부에서 일어나는 send)
  Future<T> withClientLock<T>(String host, int unitId, Future<T> Function() body) {
    return _withClientLock(_key(host, unitId), body);
  }

  // 🔹 전체 기기 차압/전류 히스토리 폴링용 타이머
  Timer? _historyTimer;
  bool _historyPollingStarted = false;

  String _key(String host, int unitId) => '$host#$unitId';

  Future<ModbusClientTcp?> _connect(String host, int unitId) async {
    final c = ModbusClientTcp(host, unitId: unitId);
    await c.connect(); // TCP 소켓 연결
    return c;
  }

  void _autoStartAlarmWatch(String host, int unitId, String name) {
    final k = _key(host, unitId);
    if (_alarmPollers.containsKey(k)) return; // 이미 감시 중
    final poller = _AlarmPoller(
      host: host,
      unitId: unitId,
      name: name, // 표시명(필요하면 아래 3-참고의 setDeviceLabel로 나중에 교체 가능)
      interval: const Duration(seconds: 1),
      ensure: ({int verifyAddress = 0}) =>
          ensureConnectedSilent(host: host, unitId: unitId, verifyAddress: verifyAddress, name: name),
    );
    _alarmPollers[k] = poller;
    poller.start();
  }

  // 헬스 체크: Holding Register #1 한 번 읽어서 슬레이브 응답 확인
  // (호출 시점엔 client가 _clients map에 등록되기 전이라 다른 곳과 contention 없음)
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
        required String name,
        int verifyAddress = 0, // 기본: 입력레지스터 #0
      })
  async {
    final k = _key(host, unitId);

    // 1) 재사용: 기존 소켓이 있고 연결 상태면 그대로 사용(매 틱 핑 제거)
    final cur = _clients[k];
    if (cur != null && cur.isConnected) {
      context.read<ConnectionRegistry>().markConnected(host, unitId);
      _autoStartAlarmWatch(host, unitId, name);
      return cur;
    }

    // 2) 새로 연결
    final nc = await _connect(host, unitId);

    // 3) 최초 연결 시에만 핑
    final healthy = await _ping(nc!, address: verifyAddress);
    if (healthy) {
      _clients[k] = nc;
      context.read<ConnectionRegistry>().markConnected(host, unitId);
      _autoStartAlarmWatch(host, unitId, name);
      return nc;
    } else {
      try { await nc.disconnect(); } catch (_) {}
      _clients.remove(k);
      context.read<ConnectionRegistry>().markDisconnected(host, unitId);
      throw Exception('Modbus slave not responding (host=$host, unitId=$unitId)');
    }
  }




  /// 🔹 한 기기의 차압/전류만 읽어서 히스토리에 넣는 내부 헬퍼
  Future<void> _pollDpAndPowerOnce(
      BuildContext context, {
        required String host,
        required int unitId,
      }) async {
    // 0~69 input register 읽기용 그룹 (MainPage에서 쓰는 거랑 동일)
    final inputs = ModbusElementsGroup(
      List.generate(70, (i) => ModbusUint16Register(
        name: 'hist_in_$i',
        type: ModbusElementType.inputRegister,
        address: i,
      )),
    );

    // 연결 확보 (기존 ensureConnected 재사용)
    final client = await ensureConnected(
      context,
      host: host,
      unitId: unitId,
      name: '$host#$unitId',
    );

    // 레지스터 읽기 (다른 곳의 send와 직렬화)
    await _withClientLock(_key(host, unitId), () async {
      await client.send(inputs.getReadRequest());
    });

    final dp = (inputs[0] as ModbusUint16Register).value?.toInt() ?? 0;
    final p1 =
        ((inputs[1] as ModbusUint16Register).value?.toDouble() ?? 0) / 10;
    final p2 =
        ((inputs[2] as ModbusUint16Register).value?.toDouble() ?? 0) / 10;

    // Provider에 히스토리 적재
    final dpHistory = context.read<DpHistory>();
    final powerHistory = context.read<PowerHistory>();

    dpHistory.addPointFor(host, unitId, dp.toDouble());
    powerHistory.addPointFor(host, unitId, 1, p1);
    powerHistory.addPointFor(host, unitId, 2, p2);
  }

  /// 🔹 전체 connectedDevices 를 1초마다 돌면서 차압/전류 히스토리 적재
  void startHistoryPolling(BuildContext context) {
    if (_historyPollingStarted) return; // 한 번만 시작
    _historyPollingStarted = true;

    _historyTimer ??=
        Timer.periodic(const Duration(seconds: 1), (Timer t) async {
          try {
            final registry = context.read<ConnectionRegistry>();
            final selected = context.read<SelectedDevice>().current;
            final devices = registry.connectedDevices;

            for (final dev in devices) {
              // ✅ 현재 선택된 기기(MainPage에서 이미 폴링 중)는 제외
              if (selected != null &&
                  selected.address == dev.host &&
                  selected.unitId == dev.unitId) {
                continue;
              }

              try {
                await _pollDpAndPowerOnce(
                  context,
                  host: dev.host,
                  unitId: dev.unitId,
                );
              } catch (e) {
                debugPrint('히스토리 폴링 실패 (${dev.host}#${dev.unitId}): $e');
              }
            }
          } catch (e) {
            debugPrint('히스토리 폴링 루프 오류: $e');
          }
        });
  }


  void stopHistoryPolling() {
    _historyTimer?.cancel();
    _historyTimer = null;
    _historyPollingStarted = false;
  }

  /// 컨텍스트 없이 조용히 연결 보장(Provider 갱신/markConnected 생략)
  Future<ModbusClientTcp> ensureConnectedSilent({
    required String host,
    required int unitId,
    required String name,
    int verifyAddress = 0, // 입력레지스터 #0 권장
  }) async {
    final k = _key(host, unitId);

    // 재사용
    final cur = _clients[k];
    if (cur != null && cur.isConnected) {
      _autoStartAlarmWatch(host, unitId, name);
      return cur;
    }

    // 새 연결
    final nc = await _connect(host, unitId);

    // 최초 연결만 가벼운 핑(입력레지스터 #0)
    final healthy = await _ping(nc!, address: verifyAddress);
    if (healthy) {
      _clients[k] = nc;
      _autoStartAlarmWatch(host, unitId, name);
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
      name: name,
      interval: interval,
      ensure: ({int verifyAddress = 0}) =>
          ensureConnectedSilent(host: host, unitId: unitId, name: name, verifyAddress: verifyAddress),
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
        required String name,
      }) async {
    final c = await ensureConnected(context, host: host, unitId: unitId, name: name);
    final reg = ModbusInt16Register(
      name: "Holding($address)",
      type: ModbusElementType.holdingRegister, // FC03
      address: address,
    );
    return _withClientLock(_key(host, unitId), () async {
      await c.send(reg.getReadRequest());
      return reg.value?.toInt();
    });
  }

  Future<List<int>?> readHoldingRange(
      BuildContext context, {
        required String host,
        required int unitId,
        required int startAddress,
        required int count,
        required String name,
      })
  async {
    try {
      final c = await ensureConnected(
        context,
        host: host,
        unitId: unitId,
        name: name,
      );

      // startAddress ~ startAddress+count-1 까지 한 번에 읽기
      final group = ModbusElementsGroup(
        List.generate(
          count,
              (i) => ModbusUint16Register(
            name: 'Holding(${startAddress + i})',
            type: ModbusElementType.holdingRegister, // FC03
            address: startAddress + i,
          ),
        ),
      );

      return await _withClientLock(_key(host, unitId), () async {
        await c.send(group.getReadRequest());
        return List<int>.generate(
          count,
              (i) => (group[i] as ModbusUint16Register).value?.toInt() ?? 0,
        );
      });
    } catch (e) {
      debugPrint('readHoldingRange error (host=$host, unitId=$unitId, start=$startAddress, count=$count): $e');
      return null;
    }
  }


  Future<bool> writeHolding(
      BuildContext context, {
        required String host,
        required int unitId,
        required int address,
        required int value,
        required String name,
      }) async {
    final c = await ensureConnected(context, host: host, unitId: unitId, name: name);
    final reg = ModbusInt16Register(
      name: "Holding($address)",
      type: ModbusElementType.holdingRegister, // FC06
      address: address,
    );
    return _withClientLock(_key(host, unitId), () async {
      await c.send(reg.getWriteRequest(value));
      return true;
    });
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

  int _pendingCode = 0;      // 지금 연속으로 관측 중인 코드
  int _pendingCount = 0;     // 같은 코드가 연속으로 몇 번 나왔는지

  void start() {
    _t?.cancel();
    _t = Timer.periodic(interval, (_) async {
      try {
        final c = await ensure(verifyAddress: 0);

        // 입력레지스터 #25: 알람 코드 (0~7)
        final reg = ModbusUint16Register(
          name: 'in_25',
          type: ModbusElementType.inputRegister, // FC04
          address: 25,
        );
        await ModbusManager.instance.withClientLock(host, unitId, () async {
          await c.send(reg.getReadRequest());
        });

        final raw = reg.value?.toInt() ?? 0;
        int cur = raw;


        // 최초 한 번은 기준값만 잡고 끝
        if (_lastCode == -1) {
          _lastCode = cur;
          _pendingCode = cur;
          _pendingCount = 1;
          return;
        }

        // 🔹 현재 읽은 값(cur)이 이전에 관측 중인 pending 값과 같은지 체크
        if (cur == _pendingCode) {
          _pendingCount++;
        } else {
          _pendingCode = cur;
          _pendingCount = 1;
        }

        // 알람 해제: "현재 상태"가 알람이었고, 값이 0으로 떨어졌을 때 즉시 처리
        // 다중 알람(코드가 5→1→0처럼 바뀌며 누적된 경우)도 일괄 해제
        if (cur == 0 && _lastCode > 0) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          debugPrint('[ALARM_CLEAR_ALL] $host#$unitId name=$name lastCode=$_lastCode at=$nowMs');
          await AlarmStore.clearAllActive(
            host: host,
            unitId: unitId,
            clearedAtMs: nowMs,
          );
          _lastCode = 0;
          // 해제 후 pending 상태도 0으로 초기화
          _pendingCode = 0;
          _pendingCount = 1;
          return;
        }

        // 같은 코드가 1번 연속 나올 때만 발생으로 인정
        const int kMinStableCount = 2; // 2번(=2초) 연속 관측
        if (cur > 0 && _pendingCount >= kMinStableCount && _lastCode != cur) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          await AlarmStore.appendOccurrence(
            host: host,
            unitId: unitId,
            name: name,
            code: cur,
            tsMs: nowMs,
          );
          _lastCode = cur;
        }

      } catch (e) {
      }
    });
  }


  void stop() {
    _t?.cancel();
    _t = null;
  }
}

