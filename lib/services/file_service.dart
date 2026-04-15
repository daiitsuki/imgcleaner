import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class FileService {
  /// 중복 이미지 처리 로직
  /// mode: 'MOVE' (이동), 'RESIZE' (50% 리사이징 후 이동), 'DELETE' (삭제)
  static Future<void> processFiles({
    required List<String> targetPaths,
    required String originalFolderPath,
    required String mode,
  }) async {
    // 대상 폴더 경로 (_duplicate 접미사 추가)
    final String duplicateDirPath = "${originalFolderPath}_duplicate";
    
    // 이동이나 리사이징 시 대상 폴더 생성
    if (mode == 'MOVE' || mode == 'RESIZE') {
      final dir = Directory(duplicateDirPath);
      if (!await dir.exists()) {
        try {
          await dir.create(recursive: true);
        } catch (e) {
          debugPrint("대상 폴더 생성 실패: $e");
          rethrow;
        }
      }
    }

    for (var path in targetPaths) {
      final sourceFile = File(path);
      if (!await sourceFile.exists()) continue;

      final fileName = p.basename(path);
      final destPath = p.join(duplicateDirPath, fileName);
      final destFile = File(destPath);
      
      try {
        switch (mode) {
          case 'MOVE':
            // Android 11+ 대응: rename 대신 copy & delete 사용
            // 1. 파일 복사
            await sourceFile.copy(destPath);
            
            // 2. 복사 성공 확인 (파일 존재 및 크기 체크)
            if (await destFile.exists() && (await destFile.length() == await sourceFile.length())) {
              // 3. 원본 삭제
              await sourceFile.delete();
            } else {
              throw FileSystemException("파일 복사 검증 실패", path);
            }
            break;
            
          case 'RESIZE':
            final bytes = await sourceFile.readAsBytes();
            final image = img.decodeImage(bytes);
            if (image != null) {
              final resized = img.copyResize(image, 
                width: (image.width * 0.5).toInt(), 
                height: (image.height * 0.5).toInt()
              );
              
              // 리사이징된 파일 저장
              await destFile.writeAsBytes(img.encodeJpg(resized));
              
              // 저장 성공 확인 후 원본 삭제
              if (await destFile.exists()) {
                await sourceFile.delete();
              }
            }
            break;
            
          case 'DELETE':
            await sourceFile.delete();
            break;
        }
      } catch (e) {
        debugPrint("파일 처리 중 오류 발생 ($path): $e");
        
        // 롤백 로직: MOVE 모드에서 복사는 됐는데 삭제 중 오류가 났거나 하는 경우
        if (mode == 'MOVE' || mode == 'RESIZE') {
          if (await destFile.exists() && await sourceFile.exists()) {
            try {
              await destFile.delete(); // 복사본 삭제 (원본이 남아있으므로)
              debugPrint("롤백 완료: 생성된 복사본 삭제됨 ($destPath)");
            } catch (rollbackError) {
              debugPrint("롤백 실패: $rollbackError");
            }
          }
        }
        
        if (e is FileSystemException) {
          debugPrint("OS Error Code: ${e.osError?.errorCode}, Message: ${e.osError?.message}");
        }
      }
    }
  }
}
