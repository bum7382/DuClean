import 'dart:async';
import 'dart:collection';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';

// 모드버스 연결을 해당 파일로 이동할 예정입니다. (미완성)

// 모드버스 연결
class DeviceKey {
  final String host;  // 기기 주소
  final int unitId; // Unit ID
  final String name;  // 기기 명

  const DeviceKey({
    required this.host,
    required this.unitId,
    required this.name,
  });

  String get id => '$host#$unitId';

  @override
  bool operator ==(Object other) =>
      other is DeviceKey && host == other.host && unitId == other.unitId;

  @override
  int get hashCode => Object.hash(host, unitId);
}

/// 기기 하나에 대한 실제 Modbus TCP 연결/폴링/스트림 래퍼
class _ModbusService {
  _ModbusService(
      this.key, {
        this.inputCount = 70,
        this.period = const Duration(seconds: 1),
      }) : _inputsGroup = ModbusElementsGroup(
    List.generate(
      inputCount,
          (i) => ModbusUint16Register(
        name: 'in_$i',
        type: ModbusElementType.inputRegister,
        address: i,
      ),
    ),
  );

  final DeviceKey key;
  final int inputCount;
  Duration period;

  ModbusClientTcp? _client;
  Timer? _poller;

  // 입력값 스냅샷 (index -> value)
  final Map<int, int> _inputs = <int, int>{};
  UnmodifiableMapView<int, int> get snapshot => UnmodifiableMapView(_inputs);

  // 값 스트림
  final _inputsCtrl =
  StreamController<UnmodifiableMapView<int, int>>.broadcast();
  Stream<UnmodifiableMapView<int, int>> get stream => _inputsCtrl.stream;

  // 연결 상태 스트림(옵션)
  final _connCtrl = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connCtrl.stream;
  bool get isConnected => _client?.isConnected ?? false;

  final ModbusElementsGroup _inputsGroup;

  Future<void> start() async {
    await _ensureConnected();
    _startPolling();
  }

  Future<void> stop() async {
    _poller?.cancel();
    _poller = null;
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
    // 연결 끊김 신호
    _safeAddConn(false);
    // 컨트롤러는 재사용할 수 있게 열어둠 (dispose에서만 닫음)
  }

  Future<void> dispose() async {
    await stop();
    await _inputsCtrl.close();
    await _connCtrl.close();
  }

  // 단발 읽기/쓰기 (Holding Register)
  Future<int?> readHolding(int address) async {
    if (!await _ensureConnected()) return null;
    final r = ModbusInt16Register(
      name: 'Holding($address)',
      type: ModbusElementType.holdingRegister,
      address: address,
    );
    await _client!.send(r.getReadRequest());
    return r.value?.toInt();
  }

  Future<bool> writeHolding(int address, int value) async {
    if (!await _ensureConnected()) return false;
    final r = ModbusInt16Register(
      name: 'Holding($address)',
      type: ModbusElementType.holdingRegister,
      address: address,
    );
    await _client!.send(r.getWriteRequest(value));
    return true;
  }

  // 내부: 폴링 시작
  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(period, (_) async {
      if (!await _ensureConnected()) return;
      try {
        await _client!.send(_inputsGroup.getReadRequest());
        bool changed = false;
        for (int i = 0; i < inputCount; i++) {
          final v =
              (_inputsGroup[i] as ModbusUint16Register).value?.toInt() ?? 0;
          if (_inputs[i] != v) {
            _inputs[i] = v;
            changed = true;
          }
        }
        if (changed) {
          _inputsCtrl.add(UnmodifiableMapView(_inputs));
        }
      } catch (_) {
        // 다음 틱에서 재시도
      }
    });
  }

  Future<bool> _ensureConnected() async {
    if (_client != null && _client!.isConnected) {
      _safeAddConn(true);
      return true;
    }
    try {
      await _client?.disconnect();
    } catch (_) {}

    try {
      final c = ModbusClientTcp(key.host, unitId: key.unitId);
      await c.connect();
      _client = c;
      _safeAddConn(true);
      return true;
    } catch (_) {
      _client = null;
      _safeAddConn(false);
      return false;
    }
  }

  void _safeAddConn(bool v) {
    if (!_connCtrl.isClosed) {
      _connCtrl.add(v);
    }
  }
}

/// 여러 기기를 Map으로 관리
class ModbusManager {
  ModbusManager._();
  static final ModbusManager instance = ModbusManager._();

  final _map = <String, _ModbusService>{}; // id -> service

  bool has(DeviceKey key) => _map.containsKey(key.id);

  bool isConnected(DeviceKey key) => _map[key.id]?.isConnected ?? false;

  Stream<bool>? connectionStream(DeviceKey key) => _map[key.id]?.connectionStream;

  /// 서비스 가져오기(없으면 생성) + 시작
  Future<_ModbusService> get(
      DeviceKey key, {
        int inputCount = 70,
        Duration pollInterval = const Duration(seconds: 1),
      }) async {
    var svc = _map[key.id];
    if (svc == null) {
      svc = _ModbusService(
        key,
        inputCount: inputCount,
        period: pollInterval,
      );
      _map[key.id] = svc;
    } else {
      // 이미 존재하면 주기만 업데이트 가능
      svc.period = pollInterval;
    }
    await svc.start();
    return svc;
  }

  Future<void> dispose(DeviceKey key) async {
    final svc = _map.remove(key.id);
    if (svc != null) {
      await svc.dispose();
    }
  }

  Future<void> disposeAll() async {
    for (final s in _map.values) {
      await s.dispose();
    }
    _map.clear();
  }

  /// 단발 헬퍼
  Future<int?> readHolding(DeviceKey key, int address) async {
    final svc = await get(key);
    return svc.readHolding(address);
  }

  Future<bool> writeHolding(DeviceKey key, int address, int value) async {
    final svc = await get(key);
    return svc.writeHolding(address, value);
  }

  /// 입력값 스트림 구독
  Future<StreamSubscription<UnmodifiableMapView<int, int>>> listenInputs(
      DeviceKey key,
      void Function(UnmodifiableMapView<int, int>) onData, {
        Function? onError,
        void Function()? onDone,
        bool? cancelOnError,
      }) async {
    final svc = await get(key);
    return svc.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
