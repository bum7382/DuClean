class DeviceInfo {
  final String name;      // 기기명
  final String address;   // IP:PORT 또는 포트명
  final int unitId;       // Modbus Unit ID
  final int number;
  final String macAddress;
  final String serial;

  const DeviceInfo({
    required this.name,
    required this.address,
    required this.unitId,
    required this.number,
    required this.macAddress,
    required this.serial,
  });
}