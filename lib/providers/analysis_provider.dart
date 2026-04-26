import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/duplicate_set.dart';
import '../services/phash_service.dart';

class AnalysisState {
  final bool isAnalyzing;
  final double progress;
  final String? currentImagePath;
  final int duplicateCount;
  final List<DuplicateSet> results;
  final String? error;
  final bool isCancelled;
  final String? folderPath; // 현재 분석된 폴더 경로 추가

  AnalysisState({
    this.isAnalyzing = false,
    this.progress = 0.0,
    this.currentImagePath,
    this.duplicateCount = 0,
    this.results = const [],
    this.error,
    this.isCancelled = false,
    this.folderPath,
  });

  AnalysisState copyWith({
    bool? isAnalyzing,
    double? progress,
    String? currentImagePath,
    int? duplicateCount,
    List<DuplicateSet>? results,
    String? error,
    bool? isCancelled,
    String? folderPath,
  }) {
    return AnalysisState(
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      progress: progress ?? this.progress,
      currentImagePath: currentImagePath ?? this.currentImagePath,
      duplicateCount: duplicateCount ?? this.duplicateCount,
      results: results ?? this.results,
      error: error ?? this.error,
      isCancelled: isCancelled ?? this.isCancelled,
      folderPath: folderPath ?? this.folderPath,
    );
  }
}

class AnalysisNotifier extends StateNotifier<AnalysisState> {
  AnalysisNotifier() : super(AnalysisState()) {
    loadSavedResults();
  }
  
  CancellationToken? _currentToken;

  Future<void> loadSavedResults() async {
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('last_analysis_results');
    final savedPath = prefs.getString('last_analysis_path');
    
    if (savedJson != null && savedPath != null) {
      final List decoded = jsonDecode(savedJson);
      final results = decoded.map((e) => DuplicateSet.fromJson(e)).toList();
      state = state.copyWith(results: results, folderPath: savedPath);
    }
  }

  Future<void> startAnalysis(String folderPath, int threshold, {DateTime? startDate, DateTime? endDate}) async {
    _currentToken = CancellationToken();
    state = state.copyWith(
      isAnalyzing: true, progress: 0.0, results: [], error: null, isCancelled: false,
      duplicateCount: 0, currentImagePath: null, folderPath: folderPath,
    );

    try {
      final results = await PHashService.analyzeFolder(
        folderPath: folderPath, threshold: threshold, token: _currentToken!,
        startDate: startDate,
        endDate: endDate,
        onProgress: (current, total, currentPath, currentResults) {
          state = state.copyWith(
            progress: current / total, currentImagePath: currentPath,
            results: currentResults,
            duplicateCount: currentResults.length,
          );
        },
      );
      
      if (_currentToken?.isCancelled == true) {
        state = state.copyWith(isAnalyzing: false, isCancelled: true);
      } else {
        state = state.copyWith(isAnalyzing: false, results: results);
        // 결과 저장
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('last_analysis_results', jsonEncode(results.map((e) => e.toJson()).toList()));
        prefs.setString('last_analysis_path', folderPath);
      }
    } catch (e) {
      state = state.copyWith(isAnalyzing: false, error: e.toString());
    }
  }

  void showCurrentResults() {
    // 분석을 중단하고 현재까지 발견된 결과로 전환
    cancelAnalysis();
    // SharedPreferences에 현재까지의 결과 저장
    saveResults();
  }

  void toggleSetExpansion(int index) {
    if (index < 0 || index >= state.results.length) return;
    
    final newResults = List<DuplicateSet>.from(state.results);
    final targetSet = newResults[index];
    newResults[index] = DuplicateSet(
      images: targetSet.images,
      isExpanded: !targetSet.isExpanded,
    );
    
    state = state.copyWith(results: newResults);
  }

  Future<void> saveResults() async {
    if (state.results.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_analysis_results', jsonEncode(state.results.map((e) => e.toJson()).toList()));
    if (state.folderPath != null) {
      await prefs.setString('last_analysis_path', state.folderPath!);
    }
  }

  void clearResults() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('last_analysis_results');
    prefs.remove('last_analysis_path');
    state = AnalysisState();
  }

  void cancelAnalysis() {
    _currentToken?.cancel();
    state = state.copyWith(isAnalyzing: false, isCancelled: true);
  }

  void reset() {
    _currentToken?.cancel();
    state = AnalysisState();
  }
}

final analysisProvider = StateNotifierProvider<AnalysisNotifier, AnalysisState>((ref) => AnalysisNotifier());
