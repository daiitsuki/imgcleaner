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

  static Future<bool> isStoragePermissionGranted() async {
    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkInt();
      // Android 13 (API 33) 이상
      if (sdkInt >= 33) {
        return await Permission.photos.isGranted || await Permission.manageExternalStorage.isGranted;
      }
      // Android 11 (API 30) 이상
      if (sdkInt >= 30) {
        return await Permission.manageExternalStorage.isGranted;
      }
      // Android 10 이하
      return await Permission.storage.isGranted;
    } else if (Platform.isIOS) {
      return await Permission.photos.isGranted;
    }
    return true;
  }

  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (!Platform.isAndroid) {
      if (Platform.isIOS) return await Permission.photos.request().isGranted;
      return true;
    }

    final sdkInt = await _getAndroidSdkInt();

    // Android 13+ 대응: READ_MEDIA_IMAGES 및 MANAGE_EXTERNAL_STORAGE 고려
    if (sdkInt >= 33) {
      // 사진 권한 먼저 요청
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted) return true;
    }

    // Android 11+ 대응: MANAGE_EXTERNAL_STORAGE (더 강력한 권한)
    if (sdkInt >= 30) {
      if (await Permission.manageExternalStorage.isGranted) return true;

      bool? proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("권한 요청 안내"),
          content: const Text(
            "중복 사진을 완벽하게 정리하려면 '모든 파일 관리 권한'이 권장됩니다.\n\n"
            "이 권한이 없으면 일부 시스템 폴더의 사진을 수정하거나 삭제할 수 없습니다."
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
        final status = await Permission.manageExternalStorage.request();
        if (status.isGranted) return true;
        return await Permission.manageExternalStorage.isGranted;
      }
      return sdkInt >= 33 ? (await Permission.photos.isGranted) : false;
    } 
    else {
      final status = await Permission.storage.request();
      if (status.isPermanentlyDenied) await openAppSettings();
      return status.isGranted;
    }
  }
}
