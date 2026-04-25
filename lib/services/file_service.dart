import 'dart:io';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FileService {
  static const _channel = MethodChannel('com.example.duplicated_img/media_scanner');

  /// 여러 파일을 한 번에 미디어 스캔 (실패 시 개별 스캔으로 전환)
  static Future<void> _scanMultipleFiles(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) return;
    
    try {
      await _channel.invokeMethod('scanMultipleFiles', {'paths': paths});
    } on MissingPluginException {
      debugPrint("scanMultipleFiles를 찾을 수 없음. 개별 스캔으로 전환합니다.");
      for (var path in paths) {
        try {
          await _channel.invokeMethod('scanFile', {'path': path});
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("미디어 일괄 스캔 오류: $e");
    }
  }

  static String _getUniquePath(String dirPath, String fileName) {
    String name = p.basenameWithoutExtension(fileName);
    String ext = p.extension(fileName);
    int counter = 1;
    String newPath = p.join(dirPath, fileName);
    while (File(newPath).existsSync()) {
      newPath = p.join(dirPath, "${name}_$counter$ext");
      counter++;
    }
    return newPath;
  }

  static Future<void> processFiles({
    required List<String> targetPaths,
    required String originalFolderPath,
    required String mode,
    Function(int current, int total)? onProgress,
  }) async {
    final String duplicateDirPath = "${originalFolderPath}_duplicate";
    final List<String> filesToScan = [];
    
    if (mode == 'MOVE' || mode == 'RESIZE') {
      final dir = Directory(duplicateDirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
    }

    final int total = targetPaths.length;
    for (int i = 0; i < total; i++) {
      final path = targetPaths[i];
      final sourceFile = File(path);
      if (!await sourceFile.exists()) continue;

      final fileName = p.basename(path);
      final destPath = (mode == 'MOVE' || mode == 'RESIZE') ? _getUniquePath(duplicateDirPath, fileName) : "";
      
      try {
        switch (mode) {
          case 'MOVE':
            await sourceFile.copy(destPath);
            await sourceFile.delete();
            filesToScan.add(path);
            filesToScan.add(destPath);
            break;
            
          case 'RESIZE':
            final bytes = await sourceFile.readAsBytes();
            final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
            final descriptor = await ui.ImageDescriptor.encoded(buffer);
            final targetW = (descriptor.width * 0.5).toInt();
            final targetH = (descriptor.height * 0.5).toInt();
            
            final codec = await descriptor.instantiateCodec(targetWidth: targetW, targetHeight: targetH);
            final frame = await codec.getNextFrame();
            final uiImage = frame.image;
            
            final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
            if (byteData != null) {
              final image = img.Image.fromBytes(
                width: targetW, 
                height: targetH, 
                bytes: byteData.buffer,
                numChannels: 4
              );
              await File(destPath).writeAsBytes(img.encodeJpg(image));
              await sourceFile.delete();
              filesToScan.add(path);
              filesToScan.add(destPath);
            }
            // 리소스 즉시 해제
            uiImage.dispose();
            descriptor.dispose();
            buffer.dispose();
            break;
            
          case 'DELETE':
            await sourceFile.delete();
            filesToScan.add(path);
            break;
        }
      } catch (e) {
        debugPrint("파일 처리 오류 ($path): $e");
      }
      onProgress?.call(i + 1, total);
    }

    // 모든 처리가 끝난 후 단 한 번만 미디어 스캔 호출 (시스템 부하 감소)
    await _scanMultipleFiles(filesToScan);
    // 시스템이 미디어 스캔을 처리할 시간을 잠시 줌
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
