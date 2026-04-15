import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';

class PermissionService {
  /// 안드로이드 SDK 버전 확인
  static Future<int> _getAndroidSdkInt() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    }
    return 0;
  }

  /// 현재 모든 파일 관리 권한이 허용되어 있는지 확인
  static Future<bool> isStoragePermissionGranted() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      if (sdkInt >= 30) {
        return await Permission.manageExternalStorage.isGranted;
      } else {
        return await Permission.storage.isGranted;
      }
    } else if (Platform.isIOS) {
      return await Permission.photos.isGranted;
    }
    return true;
  }

  /// 권한 요청 메인 로직
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) {
      if (Platform.isIOS) return await Permission.photos.request().isGranted;
      return true;
    }

    final sdkInt = await _getAndroidSdkInt();

    // Android 11 (API 30) 이상: MANAGE_EXTERNAL_STORAGE 대응
    if (sdkInt >= 30) {
      if (await Permission.manageExternalStorage.isGranted) return true;

      // 사용자에게 왜 이 권한이 필요한지 설명하는 다이얼로그 표시
      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("권한 요청 안내"),
          content: const Text(
            "중복 사진을 정리하려면 '모든 파일 관리 권한'이 반드시 필요합니다.\n\n"
            "확인을 누르면 설정 화면으로 이동하며, '이 앱에 모든 파일 관리 권한 허용'을 켜주셔야 합니다."
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("취소"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("설정으로 이동"),
            ),
          ],
        ),
      );

      if (proceed == true) {
        // 설정 화면으로 이동 (결과를 기다리지 않고 바로 리턴될 수 있음)
        final status = await Permission.manageExternalStorage.request();
        
        // 설정 화면에서 돌아온 후 다시 한 번 상태를 확인해야 함
        if (status.isGranted) return true;
        
        // 사용자가 설정에서 권한을 주지 않고 돌아온 경우
        return await Permission.manageExternalStorage.isGranted;
      }
      return false;
    } 
    
    // Android 10 이하: 기존 Storage 권한 요청
    else {
      final status = await Permission.storage.request();
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return status.isGranted;
    }
  }
}
