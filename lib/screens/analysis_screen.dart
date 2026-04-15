import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analysis_provider.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    final selectedPath = ModalRoute.of(context)!.settings.arguments as String;

    // 분석 완료 시 결과 화면으로 이동
    if (!state.isAnalyzing && state.results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/comparison', arguments: selectedPath);
      });
    }

    final bool isDone = !state.isAnalyzing;
    final bool noResults = isDone && state.results.isEmpty && state.error == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text("분석 중"),
        automaticallyImplyLeading: isDone, // 분석 완료 시에만 뒤로가기 버튼 활성화
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (noResults) ...[
                const Icon(Icons.search_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text("중복된 사진을 찾지 못했습니다.", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("뒤로 가기"),
                ),
              ] else ...[
                Text(state.isAnalyzing ? "이미지를 분석하고 있습니다..." : "분석 완료", 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                LinearProgressIndicator(
                  value: state.progress,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 16),
                Text("${(state.progress * 100).toInt()}% 완료", 
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 24),
              if (state.error != null) ...[
                Text("오류: ${state.error}", 
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("뒤로 가기"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
