import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analysis_provider.dart';
import '../providers/selection_provider.dart';
import '../services/file_service.dart';
import '../models/image_metadata.dart';

class FullScreenImageViewer extends ConsumerStatefulWidget {
  final List<ImageMetadata> images;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key, 
    required this.images, 
    required this.initialIndex
  });

  @override
  ConsumerState<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends ConsumerState<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPaths = ref.watch(selectionProvider);
    final currentImage = widget.images[_currentIndex];
    final isSelected = selectedPaths.contains(currentImage.path);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text("${_currentIndex + 1} / ${widget.images.length}", 
          style: const TextStyle(color: Colors.white, fontSize: 16)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Image.file(File(widget.images[index].path), fit: BoxFit.contain),
                ),
              );
            },
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: () => ref.read(selectionProvider.notifier).toggleSelection(currentImage.path),
                icon: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined),
                label: Text(isSelected ? "이 사진 유지함" : "삭제 대상으로 표시", 
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: isSelected ? Colors.green : Colors.red,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = ref.watch(analysisProvider);
    final selectedPaths = ref.watch(selectionProvider);
    final folderPath = ModalRoute.of(context)!.settings.arguments as String;

    final results = analysisState.results;
    
    if (results.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("결과 없음")),
        body: const Center(child: Text("중복된 사진을 찾지 못했습니다.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("중복 세트 (${results.length}개 발견)"),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: results.length,
        itemBuilder: (context, setIndex) {
          final set = results[setIndex];
          final List<String> setPaths = set.images.map((e) => e.path).toList();

          return Card(
            margin: const EdgeInsets.all(12),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Text("세트 ${setIndex + 1}", 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => ref.read(selectionProvider.notifier).selectAll(setPaths),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text("모두 선택"),
                      ),
                      TextButton.icon(
                        onPressed: () => ref.read(selectionProvider.notifier).deselectAll(setPaths),
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        label: const Text("모두 해제"),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: set.images.asMap().entries.map((entry) {
                      final int imgIndex = entry.key;
                      final img = entry.value;
                      final isSelected = selectedPaths.contains(img.path);
                      
                      return Container(
                        width: 200,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => ref.read(selectionProvider.notifier).toggleSelection(img.path),
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(9), topRight: Radius.circular(9)),
                                    child: Image.file(
                                      File(img.path), 
                                      width: 200, 
                                      height: 200, 
                                      fit: BoxFit.cover,
                                      // 메모리 절약을 위해 실제 렌더링 크기에 맞춰 디코딩 사이즈 제한
                                      cacheWidth: 400, // 200px * devicePixelRatio(대략 2.0)
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.green : Colors.white70,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                                        color: isSelected ? Colors.white : Colors.grey,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: InkWell(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(
                                        builder: (context) => FullScreenImageViewer(
                                          images: set.images, 
                                          initialIndex: imgIndex
                                        ),
                                      )),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Icon(Icons.fullscreen, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                width: double.infinity,
                                color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                      color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(isSelected ? "유지함" : "삭제대상", 
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.red,
                                      )),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomAction(context, ref, results, selectedPaths, folderPath),
    );
  }

  Widget _buildBottomAction(BuildContext context, WidgetRef ref, List results,
      Set<String> selectedPaths, String folderPath) {
    int totalImages = 0;
    for (var set in results) {
      totalImages += (set.images.length as int);
    }
    int keepCount = selectedPaths.length;
    int deleteCount = totalImages - keepCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("총 ${totalImages}장 중",
                      style: const TextStyle(fontSize: 12)),
                  Text("${keepCount}장 유지 / ${deleteCount}장 처리",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: deleteCount == 0
                    ? null
                    : () => _showProcessOptions(
                        context, ref, results, selectedPaths, folderPath),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: const Text("선택한 사진 제외하고 정리",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProcessOptions(BuildContext context, WidgetRef ref, List results,
      Set<String> selectedPaths, String folderPath) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("정리 방식 선택",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.move_to_inbox)),
                  title: const Text("다른 폴더로 이동 (권장)"),
                  subtitle: const Text("'_duplicate' 폴더로 옮겨 나중에 확인할 수 있습니다."),
                  onTap: () => _confirmAction(
                      context, ref, results, selectedPaths, folderPath, 'MOVE'),
                ),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.errorContainer,
                      child: Icon(Icons.delete_forever,
                          color: Theme.of(context).colorScheme.error)),
                  title: const Text("영구 삭제 (주의)",
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text("파일이 기기에서 즉시 삭제되며 복구할 수 없습니다."),
                  onTap: () => _confirmAction(context, ref, results,
                      selectedPaths, folderPath, 'DELETE'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmAction(BuildContext context, WidgetRef ref, List results,
      Set<String> selectedPaths, String folderPath, String mode) {
    Navigator.pop(context); // 시트 닫기

    int totalImages = 0;
    for (var set in results) {
      totalImages += (set.images.length as int);
    }
    int deleteCount = totalImages - selectedPaths.length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mode == 'DELETE' ? "영구 삭제 확인" : "이동 확인"),
        content: Text(
            "${deleteCount}장의 사진을 ${mode == 'DELETE' ? '영구 삭제' : '이동'}하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("취소")),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);

              final List<String> targetPaths = [];
              for (var set in results) {
                for (var img in set.images) {
                  if (!selectedPaths.contains(img.path)) {
                    targetPaths.add(img.path);
                  }
                }
              }

              await FileService.processFiles(
                targetPaths: targetPaths,
                originalFolderPath: folderPath,
                mode: mode,
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text("${targetPaths.length}장의 사진 처리가 완료되었습니다.")),
                );
                Navigator.popUntil(context, ModalRoute.withName('/'));
              }
            },
            style: mode == 'DELETE'
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }
}