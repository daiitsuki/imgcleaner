import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

class UpdateService {
  // 실제 업데이트 정보가 담긴 서버 URL (예: GitHub Releases API 등)
  static const String _updateInfoUrl = 'https://example.com/update.json';

  /// 업데이트 체크 및 다이얼로그 표시
  static Future<void> checkUpdate(BuildContext context, {bool showNoUpdateMsg = false}) async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      // 1. 서버에서 최신 버전 정보 가져오기 (임시 예시)
      // 실제 구현 시 http.get(_updateInfoUrl) 사용
      /*
      final response = await http.get(Uri.parse(_updateInfoUrl));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body);
      final String latestVersion = data['version'];
      final String downloadUrl = data['url'];
      */

      // 테스트를 위한 더미 데이터 (현재 버전보다 높게 설정하면 다이얼로그가 뜸)
      const String latestVersion = '1.0.1'; 
      const String downloadUrl = 'https://example.com/app.apk';

      if (_isNewerVersion(currentVersion, latestVersion)) {
        if (!context.mounted) return;
        _showUpdateDialog(context, latestVersion, downloadUrl);
      } else if (showNoUpdateMsg) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("이미 최신 버전입니다.")),
        );
      }
    } catch (e) {
      debugPrint("업데이트 체크 중 오류: $e");
    }
  }

  /// 버전 비교 (단순 문자열 비교가 아닌 세그먼트 비교)
  static bool _isNewerVersion(String current, String latest) {
    List<int> currentV = current.split('.').map(int.parse).toList();
    List<int> latestV = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestV.length; i++) {
      if (i >= currentV.length) return true;
      if (latestV[i] > currentV[i]) return true;
      if (latestV[i] < currentV[i]) return false;
    }
    return false;
  }

  /// 업데이트 안내 다이얼로그
  static void _showUpdateDialog(BuildContext context, String version, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("새 업데이트 발견"),
        content: Text("새로운 버전 ($version)이 출시되었습니다. 지금 업데이트하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("나중에"),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _startOtaUpdate(context, url);
            },
            child: const Text("업데이트"),
          ),
        ],
      ),
    );
  }

  /// 실제 다운로드 및 설치 시작
  static void _startOtaUpdate(BuildContext context, String url) {
    if (!Platform.isAndroid) return;

    try {
      OtaUpdate().execute(url, destinationFilename: 'update.apk').listen(
        (OtaEvent event) {
          debugPrint('OTA Status: ${event.status}, Progress: ${event.value}');
          
          if (event.status == OtaStatus.DOWNLOADING) {
            // 필요 시 전역 프로그레스바 표시 가능
          } else if (event.status == OtaStatus.INSTALLING) {
            debugPrint("설치 화면으로 이동합니다.");
          } else if (event.status == OtaStatus.INTERNAL_ERROR) {
            debugPrint("업데이트 중 내부 오류 발생");
          }
        },
      );
    } catch (e) {
      debugPrint('OTA 업데이트 실패: $e');
    }
  }
}
