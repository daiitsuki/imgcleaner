import 'image_metadata.dart';

/// 중복 판정된 이미지 그룹 모델
class DuplicateSet {
  final List<ImageMetadata> images;
  
  // 기본적으로 첫 번째 사진을 유지하고 나머지를 처리 대상으로 설정하는 로직에 사용
  DuplicateSet({required this.images});

  /// 이 세트를 정리함으로써 절약 가능한 총 용량 (MB)
  double get potentialSavingMB {
    if (images.length <= 1) return 0.0;
    // 가장 용량이 큰 하나만 남긴다고 가정했을 때의 절약분 (혹은 사용자가 체크 안 한 것들의 합)
    double totalSize = images.fold(0.0, (prev, element) => prev + element.sizeInMB);
    double minSize = images.map((e) => e.sizeInMB).reduce((a, b) => a < b ? a : b);
    return totalSize - minSize;
  }
}
