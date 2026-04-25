import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';
import '../models/image_metadata.dart';
import '../models/duplicate_set.dart';

class CancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

class Edge {
  final int i, j;
  final double score;
  Edge(this.i, this.j, this.score);
}

class ClusteringParams {
  final List<ImageMetadata> metaList;
  final double limit;
  ClusteringParams(this.metaList, this.limit);
}

class PHashService {
  static BigInt _computeDCTpHash(List<double> grayscale32x32) {
    final List<List<double>> matrix = List.generate(32, (i) => grayscale32x32.sublist(i * 32, (i + 1) * 32));
    final List<List<double>> dctMatrix = _applyDCT2D(matrix);
    final List<double> lowFreq = [];
    for (int y = 0; y < 12; y++) {
      for (int x = 0; x < 12; x++) {
        if (x == 0 && y == 0) continue;
        lowFreq.add(dctMatrix[y][x]);
      }
    }
    final double median = (lowFreq.toList()..sort())[lowFreq.length ~/ 2];
    BigInt hash = BigInt.zero;
    for (int i = 0; i < lowFreq.length; i++) {
      if (lowFreq[i] > median) hash |= (BigInt.one << i);
    }
    return hash;
  }

  static List<List<double>> _applyDCT2D(List<List<double>> input) {
    int N = 32;
    List<List<double>> temp = List.generate(N, (_) => List.filled(N, 0.0));
    List<List<double>> output = List.generate(N, (_) => List.filled(N, 0.0));
    for (int i = 0; i < N; i++) {
      for (int j = 0; j < N; j++) {
        double sum = 0;
        for (int k = 0; k < N; k++) sum += input[i][k] * cos(pi / N * (k + 0.5) * j);
        temp[i][j] = sum;
      }
    }
    for (int j = 0; j < N; j++) {
      for (int i = 0; i < N; i++) {
        double sum = 0;
        for (int k = 0; k < N; k++) sum += temp[k][j] * cos(pi / N * (k + 0.5) * i);
        output[i][j] = sum;
      }
    }
    return output;
  }

  static Future<ImageMetadata?> extractFeatures(String path, CancellationToken token) async {
    if (token.isCancelled) return null;
    try {
      final File file = File(path);
      final Uint8List bytes = await file.readAsBytes();
      
      final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final ui.ImageDescriptor descriptor = await ui.ImageDescriptor.encoded(buffer);
      
      // 1. Sharpness (128x128)
      final ui.Codec sharpCodec = await descriptor.instantiateCodec(targetWidth: 128, targetHeight: 128);
      final ui.FrameInfo sharpFrame = await sharpCodec.getNextFrame();
      final ByteData? sharpData = await sharpFrame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      double sharpness = 0;
      if (sharpData != null) {
        final Uint8List sPixels = sharpData.buffer.asUint8List();
        final List<double> sGray = [];
        for (int i = 0; i < 16384; i++) sGray.add(0.299 * sPixels[i*4] + 0.587 * sPixels[i*4+1] + 0.114 * sPixels[i*4+2]);
        for (int y = 1; y < 127; y++) {
          for (int x = 1; x < 127; x++) {
            double c = sGray[y * 128 + x];
            double d = (c * 4) - sGray[(y-1)*128+x] - sGray[(y+1)*128+x] - sGray[y*128+x-1] - sGray[y*128+x+1];
            sharpness += d * d;
          }
        }
        sharpness /= 16384;
      }
      sharpFrame.image.dispose();
      if (token.isCancelled) { descriptor.dispose(); buffer.dispose(); return null; }

      // 2. pHash/Hist (32x32)
      final ui.Codec analCodec = await descriptor.instantiateCodec(targetWidth: 32, targetHeight: 32);
      final ui.FrameInfo analFrame = await analCodec.getNextFrame();
      final ByteData? analData = await analFrame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (analData == null) return null;
      final Uint8List pixels = analData.buffer.asUint8List();
      final List<double> grayscale = [];
      final List<double> rHist = List.filled(8, 0.0), gHist = List.filled(8, 0.0), bHist = List.filled(8, 0.0);
      for (int i = 0; i < 1024; i++) {
        int r = pixels[i*4], g = pixels[i*4+1], b = pixels[i*4+2];
        grayscale.add(0.299 * r + 0.587 * g + 0.114 * b);
        rHist[r ~/ 32]++; gHist[g ~/ 32]++; bHist[b ~/ 32]++;
      }
      final List<double> histogram = [...rHist, ...gHist, ...bHist].map((v) => v / 1024).toList();
      final BigInt pHash = _computeDCTpHash(grayscale);
      analFrame.image.dispose();

      // 3. EXIF 추출 (exif 패키지 사용)
      DateTime? dateTime;
      try {
        final Map<String, IfdTag> data = await readExifFromBytes(bytes);
        if (data.containsKey('Image DateTime')) {
          final String dateStr = data['Image DateTime']!.toString();
          // 포맷: 2023:10:25 14:30:05
          final parts = dateStr.split(' ');
          final dateParts = parts[0].split(':');
          final timeParts = parts[1].split(':');
          dateTime = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
            int.parse(timeParts[2]),
          );
        }
      } catch (_) {}
      dateTime ??= file.lastModifiedSync();
      
      final int w = descriptor.width;
      final int h = descriptor.height;
      descriptor.dispose();
      buffer.dispose();

      return ImageMetadata(
        path: path, fileName: path.split(Platform.pathSeparator).last,
        hash: pHash, size: file.lengthSync(), dateTime: dateTime!,
        width: w, height: h, sharpness: sharpness, histogram: histogram,
      );
    } catch (e) { return null; }
  }

  static double _getScore(ImageMetadata m1, ImageMetadata m2) {
    if ((m1.aspectRatio - m2.aspectRatio).abs() > 0.15) return 1.0;
    int hamming = 0;
    BigInt x = m1.hash ^ m2.hash;
    while (x > BigInt.zero) { x &= (x - BigInt.one); hamming++; }
    double pHashScore = hamming / 143.0;
    double histDist = 0;
    for (int i = 0; i < m1.histogram.length; i++) histDist += pow(m1.histogram[i] - m2.histogram[i], 2);
    double histScore = sqrt(histDist) / sqrt(2);
    double nameScore = 1.0;
    String n1 = m1.fileName.toLowerCase(), n2 = m2.fileName.toLowerCase();
    if (n1 == n2) {
      nameScore = 0.0;
    } else {
      String b1 = n1.replaceAll(RegExp(r'\(\d+\)|_copy| - 복사본'), '').split('.').first;
      String b2 = n2.replaceAll(RegExp(r'\(\d+\)|_copy| - 복사본'), '').split('.').first;
      if (b1 == b2) nameScore = 0.2;
    }
    // 최종 점수 합산 (pHash 75% + Histogram 20% + Name 5%)
    return (pHashScore * 0.75) + (histScore * 0.20) + (nameScore * 0.05);
  }

  /// 더 유연한 클러스터링을 위해 Single-Linkage(Connected Components) 방식으로 수행
  static List<DuplicateSet> _performClustering(ClusteringParams params) {
    final metaList = params.metaList;
    final limit = params.limit;
    final int n = metaList.length;
    final List<Edge> edges = [];

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        double score = _getScore(metaList[i], metaList[j]);
        bool isRecent = metaList[j].dateTime.difference(metaList[i].dateTime).inMinutes <= 5;
        if (isRecent || score < 0.15) {
          if (score <= limit) edges.add(Edge(i, j, score));
        } else {
          if (metaList[j].dateTime.difference(metaList[i].dateTime).inHours > 1) break;
        }
      }
    }
    
    edges.sort((a, b) => a.score.compareTo(b.score));
    final List<int> clusterMap = List.generate(n, (i) => i);
    final List<List<int>?> clusters = List.generate(n, (i) => [i]);

    for (var edge in edges) {
      int c1Idx = clusterMap[edge.i], c2Idx = clusterMap[edge.j];
      if (c1Idx == c2Idx) continue;

      // Single-Linkage: 한 쌍이라도 비슷하면 즉시 그룹 통합
      final c1 = clusters[c1Idx]!, c2 = clusters[c2Idx]!;
      c1.addAll(c2);
      for (int b in c2) clusterMap[b] = c1Idx;
      clusters[c2Idx] = null;
    }

    return clusters.where((c) => c != null && c.length > 1)
        .map((c) => DuplicateSet(images: c!.map((idx) => metaList[idx]).toList()))
        .toList();
  }

  static Future<List<DuplicateSet>> analyzeFolder({
    required String folderPath,
    required int threshold,
    required CancellationToken token,
    required Function(int current, int total, String? currentPath, int duplicateCount) onProgress,
  }) async {
    final dir = Directory(folderPath);
    final List<String> filePaths = [];
    await for (var entity in dir.list(recursive: false, followLinks: false)) {
      if (token.isCancelled) return [];
      if (entity is File && entity.path.toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png|heic)$'))) {
        filePaths.add(entity.path);
      }
    }
    
    if (filePaths.isEmpty) return [];

    final List<ImageMetadata> metaList = [];
    final int total = filePaths.length;
    final int concurrency = Platform.numberOfProcessors;
    for (int i = 0; i < total; i += concurrency) {
      if (token.isCancelled) return [];
      final int end = (i + concurrency < total) ? i + concurrency : total;
      final List<Future<ImageMetadata?>> batch = [];
      for (int j = i; j < end; j++) batch.add(extractFeatures(filePaths[j], token));
      final results = await Future.wait(batch);
      metaList.addAll(results.whereType<ImageMetadata>());
      onProgress(metaList.length, total, filePaths[i], 0);
    }

    if (token.isCancelled) return [];
    metaList.sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final double limit = 0.10 + (threshold / 100) * 0.4;

    // 클러스터링 연산을 Isolate에서 실행 (메인 스레드 멈춤 방지)
    final results = await compute(_performClustering, ClusteringParams(metaList, limit));
    onProgress(total, total, null, results.length);
    return results;
  }
}
