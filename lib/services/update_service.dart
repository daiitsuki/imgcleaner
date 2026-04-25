import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ota_update/ota_update.dart';

class UpdateService {
  // GitHub 저장소의 Raw JSON 파일 주소
  static const String _updateInfoUrl =
      'https://raw.githubusercontent.com/daiitsuki/imgcleaner/refs/heads/master/update.json';

  /// 업데이트 체크 및 다이얼로그 표시
  static Future<void> checkUpdate(BuildContext context,
      {bool showNoUpdateMsg = false}) async {
    try {
      // 1. 현재 앱 버전 정보 가져오기
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      // 2. GitHub 서버에서 최신 버전 정보 가져오기
      final response = await http
          .get(Uri.parse(_updateInfoUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        if (showNoUpdateMsg && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("업데이트 정보를 가져올 수 없습니다.")),
          );
        }
        return;
      }

      final data = json.decode(response.body);
      final String latestVersion = data['version'] ?? "1.0.0";
      final String downloadUrl = data['url'] ?? "";
      final String changelog = data['changelog'] ?? "새로운 버전이 출시되었습니다.";

      // 3. 버전 비교 후 업데이트 창 표시
      if (_isNewerVersion(currentVersion, latestVersion)) {
        if (!context.mounted) return;
        _showUpdateDialog(context, latestVersion, downloadUrl, changelog);
      } else if (showNoUpdateMsg) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("이미 최신 버전(v$currentVersion)을 사용 중입니다.")),
        );
      }
    } catch (e) {
      debugPrint("업데이트 체크 중 오류: $e");
      if (showNoUpdateMsg && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("업데이트 확인 중 오류가 발생했습니다.")),
        );
      }
    }
  }

  /// 버전 비교 로직 (1.0.0 형식을 숫자 리스트로 변환하여 비교)
  static bool _isNewerVersion(String current, String latest) {
    try {
      List<int> currentV =
          current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> latestV =
          latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < latestV.length; i++) {
        if (i >= currentV.length) return true;
        if (latestV[i] > currentV[i]) return true;
        if (latestV[i] < currentV[i]) return false;
      }
    } catch (e) {
      debugPrint("버전 비교 오류: $e");
    }
    return false;
  }

  /// 업데이트 안내 다이얼로그
  static void _showUpdateDialog(
      BuildContext context, String version, String url, String changelog) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue),
            const SizedBox(width: 10),
            Text("새 업데이트 (v$version)"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("새로운 기능 및 변경 사항:"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(changelog, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 16),
            const Text("지금 업데이트하시겠습니까?"),
          ],
        ),
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
            child: const Text("지금 업데이트"),
          ),
        ],
      ),
    );
  }

  /// 실제 다운로드 및 설치 시작
  static void _startOtaUpdate(BuildContext context, String url) {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("안드로이드 기기에서만 자동 업데이트가 가능합니다.")),
      );
      return;
    }

    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("다운로드 주소가 올바르지 않습니다.")),
      );
      return;
    }

    try {
      // 설치 다이얼로그를 띄우지 않고 백그라운드에서 진행되므로 힌트 제공
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("업데이트 다운로드를 시작합니다. 잠시만 기다려주세요..."),
          duration: Duration(seconds: 5),
        ),
      );

      OtaUpdate()
          .execute(url, destinationFilename: 'imgcleaner_update.apk')
          .listen((OtaEvent event) {
        debugPrint('OTA Status: ${event.status}, Progress: ${event.value}');

        if (event.status == OtaStatus.INSTALLING) {
          debugPrint("설치를 시작합니다.");
        } else if (event.status == OtaStatus.INTERNAL_ERROR) {
          _showError(context, "업데이트 중 내부 오류가 발생했습니다.");
        } else if (event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR) {
          _showError(context, "파일 설치 권한이 거부되었습니다.");
        }
      }, onError: (e) {
        _showError(context, "다운로드 실패: $e");
      });
    } catch (e) {
      _showError(context, "업데이트 엔진 실행 실패: $e");
    }
  }

  static void _showError(BuildContext context, String msg) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
