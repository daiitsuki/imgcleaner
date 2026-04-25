import 'dart:io';

class ImageMetadata {
  final String path;
  final String fileName;
  final BigInt hash;
  final int size;
  final DateTime dateTime;
  final int width;
  final int height;
  final double sharpness;
  final List<double> histogram;

  ImageMetadata({
    required this.path, required this.fileName, required this.hash,
    required this.size, required this.dateTime, required this.width,
    required this.height, required this.sharpness, required this.histogram,
  });

  double get sizeInMB => size / (1024 * 1024);
  double get aspectRatio => width / height;

  Map<String, dynamic> toJson() => {
    'path': path, 'fileName': fileName, 'hash': hash.toString(),
    'size': size, 'dateTime': dateTime.toIso8601String(),
    'width': width, 'height': height, 'sharpness': sharpness,
    'histogram': histogram,
  };

  factory ImageMetadata.fromJson(Map<String, dynamic> json) => ImageMetadata(
    path: json['path'], fileName: json['fileName'],
    hash: BigInt.parse(json['hash']), size: json['size'],
    dateTime: DateTime.parse(json['dateTime']),
    width: json['width'], height: json['height'],
    sharpness: (json['sharpness'] as num).toDouble(),
    histogram: (json['histogram'] as List).map((e) => (e as num).toDouble()).toList(),
  );
}
