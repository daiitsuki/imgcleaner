import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analysis_provider.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analysisProvider);
    final selectedPath = ModalRoute.of(context)!.settings.arguments as String;

    if (!state.isAnalyzing && state.results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/comparison',
            arguments: selectedPath);
      });
    }

    final bool isDone = !state.isAnalyzing;
    final bool noResults = isDone &&
        state.results.isEmpty &&
        state.error == null &&
        !state.isCancelled;
    final bool isCancelled = state.isCancelled;

    return Scaffold(
      appBar: AppBar(
        title: const Text("분석 중"),
        automaticallyImplyLeading: isDone || isCancelled,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (noResults) ...[
                if (state.progress > 0) ...[
                  // 모든 사진을 검사했으나 중복이 없는 경우
                  const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text("중복된 사진이 없습니다.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("정리할 사진 없이 모든 사진이 깔끔합니다!", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("홈으로 돌아가기")),
                ] else ...[
                  // 폴더에 사진 자체가 없는 경우
                  const Icon(Icons.image_not_supported_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("분석할 사진이 없습니다.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("선택하신 기간 또는 폴더에 이미지 파일이 있는지 확인해 주세요.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("다른 설정으로 시도하기")),
                ],
              ] else if (isCancelled) ...[
                const Icon(Icons.cancel_outlined,
                    size: 64, color: Colors.orange),
                const SizedBox(height: 16),
                const Text("분석이 취소되었습니다.",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("뒤로 가기")),
              ] else ...[
                // 실시간 미리보기 제거됨
                const Icon(Icons.search, size: 80, color: Colors.blue),
                const SizedBox(height: 32),
                _buildDynamicStatus(state),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: state.progress,
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                ),
                const SizedBox(height: 12),
                Text("${(state.progress * 100).toInt()}% 분석 완료",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey)),

                if (state.results.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("발견된 중복: ${state.results.length}세트",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () => ref
                            .read(analysisProvider.notifier)
                            .showCurrentResults(),
                        child: const Row(
                          children: [
                            Text("지금까지 찾은 것만 보기"),
                            Icon(Icons.chevron_right, size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.results.length,
                      itemBuilder: (context, index) {
                        final set = state.results[index];
                        return Container(
                          width: 100,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(File(set.images.first.path)),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8)),
                              ),
                              child: Text(
                                "${set.images.length}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 40),
                if (state.isAnalyzing)
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.read(analysisProvider.notifier).cancelAnalysis(),
                    icon: const Icon(Icons.stop),
                    label: const Text("분석 중단"),
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 24),
                Text("오류: ${state.error}",
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("뒤로 가기")),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicStatus(AnalysisState state) {
    String text = "이미지를 분석하고 있습니다...";
    if (state.progress > 0.9)
      text = "거의 다 됐어요! 중복 세트 구성 중...";
    else if (state.duplicateCount > 0)
      text = "${state.duplicateCount}개의 중복 세트 발견!";

    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}
