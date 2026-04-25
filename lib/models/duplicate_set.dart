import 'image_metadata.dart';

class DuplicateSet {
  final List<ImageMetadata> images;
  late final int recommendedIndex;
  
  DuplicateSet({required this.images}) {
    recommendedIndex = _calculateRecommendedIndex();
  }

  int _calculateRecommendedIndex() {
    int bestIdx = 0;
    for (int i = 1; i < images.length; i++) {
      final best = images[bestIdx];
      final current = images[i];
      if ((current.sharpness - best.sharpness).abs() > 0.05) {
        if (current.sharpness > best.sharpness) { bestIdx = i; continue; }
      }
      int bestPixels = best.width * best.height;
      int currentPixels = current.width * current.height;
      if (currentPixels > bestPixels) { bestIdx = i; continue; }
      if (current.size > best.size) bestIdx = i;
    }
    return bestIdx;
  }

  ImageMetadata get recommendedImage => images[recommendedIndex];

  double get potentialSavingMB {
    if (images.length <= 1) return 0.0;
    double totalSize = images.fold(0.0, (prev, element) => prev + element.sizeInMB);
    return totalSize - recommendedImage.sizeInMB;
  }

  Map<String, dynamic> toJson() => {
    'images': images.map((e) => e.toJson()).toList(),
  };

  factory DuplicateSet.fromJson(Map<String, dynamic> json) => DuplicateSet(
    images: (json['images'] as List).map((e) => ImageMetadata.fromJson(e)).toList(),
  );
}
