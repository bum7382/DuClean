import 'package:flutter/foundation.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiFinderService {
  static final WifiFinderService _instance = WifiFinderService._internal();
  factory WifiFinderService() => _instance;
  WifiFinderService._internal();

  /// 주변의 모든 'DUCLEAN_' 기기를 찾아 MAC 주소 리스트로 반환
  Future<List<String>> scanAndGetList() async {
    final List<String> foundDevices = [];

    try {
      // 1. 권한 확인
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) return []; // 권한 없으면 빈 리스트
      }

      // 2. 스캔 요청 (실패해도 진행)
      try {
        await WiFiScan.instance.startScan();
      } catch (e) {
        debugPrint('[WiFi] 스캔 요청 무시하고 목록 읽기 시도');
      }

      // 3. 결과 가져오기
      final results = await WiFiScan.instance.getScannedResults();
      debugPrint('[WiFi] 총 감지된 신호: ${results.length}개');

      // 4. 'DUCLEAN_' 필터링 및 수집
      for (var ap in results) {
        if (ap.ssid.isNotEmpty && ap.ssid.startsWith("DUCLEAN_")) {
          // "DUCLEAN_AABBCC" -> "AABBCC" 추출
          final mac = ap.ssid.substring(8);

          // 중복 제거 (가끔 같은 게 두 번 잡힐 때가 있음)
          if (!foundDevices.contains(mac)) {
            foundDevices.add(mac);
          }
        }
      }

      return foundDevices;

    } catch (e) {
      debugPrint('[WiFi] 에러: $e');
      return [];
    }
  }
}