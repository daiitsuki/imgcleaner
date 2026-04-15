import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/duplicate_set.dart';
import '../services/phash_service.dart';

/// 분석 상태를 관리하는 StateNotifier
class AnalysisState {
  final bool isAnalyzing;
  final double progress;
  final String currentFile;
  final List<DuplicateSet> results;
  final String? error;

  AnalysisState({
    this.isAnalyzing = false,
    this.progress = 0.0,
    this.currentFile = "",
    this.results = const [],
    this.error,
  });

  AnalysisState copyWith({
    bool? isAnalyzing,
    double? progress,
    String? currentFile,
    List<DuplicateSet>? results,
    String? error,
  }) {
    return AnalysisState(
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      progress: progress ?? this.progress,
      currentFile: currentFile ?? this.currentFile,
      results: results ?? this.results,
      error: error ?? this.error,
    );
  }
}

class AnalysisNotifier extends StateNotifier<AnalysisState> {
  AnalysisNotifier() : super(AnalysisState());

  Future<void> startAnalysis(String folderPath, int threshold) async {
    state = state.copyWith(isAnalyzing: true, progress: 0.0, results: [], error: null);

    try {
      final results = await PHashService.analyzeFolder(
        folderPath: folderPath,
        threshold: threshold,
        onProgress: (current, total) {
          state = state.copyWith(progress: current / total);
        },
      );
      state = state.copyWith(isAnalyzing: false, results: results);
    } catch (e) {
      state = state.copyWith(isAnalyzing: false, error: e.toString());
    }
  }

  void reset() {
    state = AnalysisState();
  }
}

final analysisProvider = StateNotifierProvider<AnalysisNotifier, AnalysisState>((ref) {
  return AnalysisNotifier();
});
