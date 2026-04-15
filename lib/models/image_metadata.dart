import 'dart:io';

/// 개별 이미지의 메타데이터와 계산된 pHash를 저장하는 모델
class ImageMetadata {
  final String path;
  final String fileName;
  final BigInt hash; // 64비트 pHash 저장
  final int size; // byte 단위 파일 크기

  ImageMetadata({
    required this.path,
    required this.fileName,
    required this.hash,
    required this.size,
  });

  double get sizeInMB => size / (1024 * 1024);
}
