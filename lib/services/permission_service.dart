import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  static Future<int> _getAndroidSdkInt() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    }
    return 0;
  }

  /// 현재 필요한 핵심 권한이 허용되어 있는지 확인
  static Future<bool> isStoragePermissionGranted() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      // Android 11 (API 30) 이상: 반드시 '모든 파일 관리 권한'이 있어야 함
      if (sdkInt >= 30) {
        return await Permission.manageExternalStorage.isGranted;
      }
      // Android 10 이하: 기존 Storage 권한 확인
      return await Permission.storage.isGranted;
    } else if (Platform.isIOS) {
      return await Permission.photos.isGranted;
    }
    return true;
  }

  /// 권한 요청 및 설정 화면 유도
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) {
      if (Platform.isIOS) return await Permission.photos.request().isGranted;
      return true;
    }

    final sdkInt = await _getAndroidSdkInt();

    // Android 11+ 대응: MANAGE_EXTERNAL_STORAGE (가장 강력하고 확실한 권한)
    if (sdkInt >= 30) {
      if (await Permission.manageExternalStorage.isGranted) return true;

      // 사용자에게 왜 이 권한이 필요한지 명확히 설명
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("권한 허용 안내"),
          content: const Text(
            "사진을 이동하거나 삭제하려면 '모든 파일 관리 권한'이 반드시 필요합니다.\n\n"
            "확인을 누르시면 설정 화면으로 이동합니다.\n'중복 사진 제거기'를 찾아 권한을 켜주세요."
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("취소"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("설정하러 가기"),
            ),
          ],
        ),
      );

      if (proceed == true) {
        // 이 호출은 안드로이드 시스템의 '모든 파일 액세스' 설정 페이지를 직접 엽니다.
        await Permission.manageExternalStorage.request();
        
        // 사용자가 설정에서 돌아왔을 때 다시 한번 상태 확인
        return await Permission.manageExternalStorage.isGranted;
      }
      return false;
    } 
    // Android 10 이하 대응
    else {
      final status = await Permission.storage.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return status.isGranted;
    }
  }
}
