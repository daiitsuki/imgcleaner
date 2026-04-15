import 'dart:io';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import '../models/image_metadata.dart';
import '../models/duplicate_set.dart';

class PHashService {
  /// 두 해시 간의 Hamming Distance를 계산
  static int calculateHammingDistance(BigInt h1, BigInt h2) {
    BigInt x = h1 ^ h2;
    int distance = 0;
    while (x > BigInt.zero) {
      if (x & BigInt.one == BigInt.one) distance++;
      x >>= 1;
    }
    return distance;
  }

  /// [사용자 제안 최적화] 이미지를 아주 작은 크기로 네이티브 디코딩 후 pHash 생성
  /// 이 방식은 고해상도 이미지를 전부 메모리에 올리지 않아 OOM을 완벽히 방지합니다.
  static Future<BigInt> generatePHashNative(String path) async {
    try {
      final File file = File(path);
      final Uint8List bytes = await file.readAsBytes();

      // 1. 네이티브 엔진을 사용해 이미지를 처음부터 16x16 크기로만 디코딩 (메모리 절약 핵심)
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
      
      // 16x16 정도로 타겟 사이즈를 잡아 성능과 정확도의 균형을 맞춤
      final ui.Codec codec = await descriptor.instantiateCodec(
        targetWidth: 16, 
        targetHeight: 16
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image uiImage = frameInfo.image;

      // 2. 픽셀 데이터 추출 (RGBA_8888)
      final ByteData? byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return BigInt.zero;
      final Uint8List pixels = byteData.buffer.asUint8List();

      // 3. 16x16 데이터를 8x8 평균 해시로 변환
      int totalLuminance = 0;
      final List<int> luminanceList = [];

      // 16x16 -> 8x8 샘플링 및 그레이스케일 변환
      for (int y = 0; y < 16; y += 2) {
        for (int x = 0; x < 16; x += 2) {
          int offset = (y * 16 + x) * 4;
          // 간단한 그레이스케일 변환: (R + G + B) / 3
          int luminance = (pixels[offset] + pixels[offset + 1] + pixels[offset + 2]) ~/ 3;
          luminanceList.add(luminance);
          totalLuminance += luminance;
        }
      }

      final int avgLuminance = totalLuminance ~/ 64;
      BigInt hash = BigInt.zero;
      for (int i = 0; i < 64; i++) {
        if (luminanceList[i] >= avgLuminance) {
          hash |= (BigInt.one << i);
        }
      }

      // 리소스 해제
      uiImage.dispose();
      descriptor.dispose();
      buffer.dispose();

      return hash;
    } catch (e) {
      debugPrint("Native Hash 생성 실패 ($path): $e");
      return BigInt.zero;
    }
  }

  /// 모든 이미지에 대해 병렬 해시 계산 및 그룹화
  static Future<List<DuplicateSet>> analyzeFolder({
    required String folderPath,
    required int threshold,
    required Function(int current, int total) onProgress,
  }) async {
    final dir = Directory(folderPath);
    final List<File> files = dir.listSync()
        .whereType<File>()
        .where((f) {
          final path = f.path.toLowerCase();
          return path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');
        })
        .toList();

    if (files.isEmpty) return [];

    onProgress(0, files.length);

    final List<ImageMetadata?> metadataListTemp = List.filled(files.length, null);
    
    // 네이티브 디코딩을 사용하므로 동시 처리 개수를 다시 늘려도 안전합니다.
    final int concurrency = Platform.numberOfProcessors;
    int completedCount = 0;

    // 동시 실행을 제어하면서 처리
    for (int i = 0; i < files.length; i += concurrency) {
      final int end = (i + concurrency < files.length) ? i + concurrency : files.length;
      final List<Future<void>> batch = [];

      for (int j = i; j < end; j++) {
        final int index = j;
        final String filePath = files[index].path;
        
        batch.add(() async {
          // compute 대신 직접 비동기 호출 (네이티브 코덱은 비동기로 충분히 효율적)
          final hash = await generatePHashNative(filePath);
          if (hash != BigInt.zero) {
            metadataListTemp[index] = ImageMetadata(
              path: filePath,
              fileName: filePath.split(Platform.pathSeparator).last,
              hash: hash,
              size: File(filePath).lengthSync(),
            );
          }
          completedCount++;
          onProgress(completedCount, files.length);
        }());
      }
      await Future.wait(batch);
    }

    final List<ImageMetadata> metadataList = metadataListTemp.whereType<ImageMetadata>().toList();

    // 2. Hamming Distance 기반 그룹화 (이미지 수가 많을 경우 최적화)
    final List<DuplicateSet> sets = [];
    final Set<int> processedIndices = {};

    for (int i = 0; i < metadataList.length; i++) {
      if (processedIndices.contains(i)) continue;

      final List<ImageMetadata> currentSet = [metadataList[i]];
      
      // 내부 루프에서도 처리된 인덱스는 건너뜀
      for (int j = i + 1; j < metadataList.length; j++) {
        if (processedIndices.contains(j)) continue;

        // Hamming Distance 계산
        int distance = calculateHammingDistance(
          metadataList[i].hash, 
          metadataList[j].hash
        );

        if (distance <= threshold) {
          currentSet.add(metadataList[j]);
          processedIndices.add(j);
        }
      }

      if (currentSet.length > 1) {
        processedIndices.add(i);
        sets.add(DuplicateSet(images: currentSet));
      }
    }
    return sets;
  }
}
