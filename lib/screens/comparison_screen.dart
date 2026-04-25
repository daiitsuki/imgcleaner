import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analysis_provider.dart';
import '../providers/selection_provider.dart';
import '../services/file_service.dart';
import '../models/image_metadata.dart';
import '../models/duplicate_set.dart';

class ComparisonScreen extends ConsumerStatefulWidget {
  const ComparisonScreen({super.key});

  @override
  ConsumerState<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends ConsumerState<ComparisonScreen> {
  final Map<int, bool> _expandedSets = {}; 

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(analysisProvider);
    final selectedPaths = ref.watch(selectionProvider);
    final results = analysisState.results;
    final String folderPath = (ModalRoute.of(context)!.settings.arguments as String?) ?? analysisState.folderPath ?? "";

    if (results.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("결과 없음")),
        body: const Center(child: Text("중복된 사진을 찾지 못했습니다.")),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        bool? shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("나가기"),
            content: const Text("작업 내용이 임시 저장됩니다. 나중에 홈 화면에서 이어서 정리할 수 있습니다."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("확인")),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("중복 정리 (${results.length}세트)"),
          actions: [
            if (selectedPaths.isEmpty)
              IconButton(
                icon: const Icon(Icons.auto_fix_high, color: Colors.orange),
                onPressed: () => _applyGlobalSmartCheck(results),
                tooltip: "스마트 체크",
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.red),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(selectionProvider.notifier).clear();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("모든 선택이 초기화되었습니다.")));
                },
                tooltip: "전체 선택 취소",
              ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: Colors.blue.shade50,
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue),
                  SizedBox(width: 8),
                  Text("정리할 사진을 선택해 주세요 (지우거나 이동할 대상)", 
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 140),
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final set = results[index];
                  final isExpanded = _expandedSets[index] ?? true;
                  return _buildCollapsibleSet(index, set, isExpanded, selectedPaths);
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomAction(context, ref, results, selectedPaths, folderPath),
      ),
    );
  }

  void _applyGlobalSmartCheck(List<DuplicateSet> results) async {
    bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("스마트 체크"),
        content: const Text("모든 세트에 대해 추천 사진만 제외하고 정리를 위해 자동 선택합니다. 기존 선택은 초기화됩니다. 진행하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("진행")),
        ],
      ),
    );

    if (proceed != true) return;

    HapticFeedback.heavyImpact();
    final List<String> toSelect = [];
    for (var set in results) {
      for (int i = 0; i < set.images.length; i++) {
        if (i != set.recommendedIndex) toSelect.add(set.images[i].path);
      }
    }
    ref.read(selectionProvider.notifier).clear();
    ref.read(selectionProvider.notifier).selectAll(toSelect);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("추천 사진만 제외하고 모두 선택되었습니다.")));
    }
  }

  void _toggleSetSmartCheck(int setIndex, DuplicateSet set, Set<String> currentSelected) {
    HapticFeedback.mediumImpact();
    final setPaths = set.images.map((e) => e.path).toSet();
    final isAnySelectedInSet = setPaths.any((p) => currentSelected.contains(p));

    if (isAnySelectedInSet) {
      ref.read(selectionProvider.notifier).deselectAll(setPaths.toList());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("세트 ${setIndex + 1}의 선택을 취소했습니다."), duration: const Duration(seconds: 1)));
    } else {
      final List<String> toSelect = [];
      for (int i = 0; i < set.images.length; i++) {
        if (i != set.recommendedIndex) toSelect.add(set.images[i].path);
      }
      ref.read(selectionProvider.notifier).selectAll(toSelect);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("세트 ${setIndex + 1}의 추천 사진 제외 선택 완료"), duration: const Duration(seconds: 1)));
    }
  }

  Widget _buildCollapsibleSet(int index, DuplicateSet set, bool isExpanded, Set<String> selectedPaths) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isExpanded ? 1.0 : 0.6,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: isExpanded ? 3 : 0,
        color: isExpanded ? Colors.white : Colors.grey.shade100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expandedSets[index] = !isExpanded),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: isExpanded ? Colors.blue.shade100 : Colors.green.shade100,
                      child: Text("${index + 1}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text("세트 ${index + 1} (${set.images.length}장)", 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isExpanded ? Colors.black87 : Colors.grey)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.auto_fix_normal, size: 20, color: Colors.orange),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _toggleSetSmartCheck(index, set, selectedPaths),
                    ),
                    const SizedBox(width: 16),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.grey),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, childAspectRatio: 0.85, mainAxisSpacing: 8, crossAxisSpacing: 8,
                ),
                itemCount: set.images.length,
                itemBuilder: (context, imgIdx) {
                  final img = set.images[imgIdx];
                  final isBest = set.recommendedIndex == imgIdx;
                  final isToDelete = selectedPaths.contains(img.path);
                  return _buildImageItem(img, isBest, isToDelete, set.images);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageItem(ImageMetadata img, bool isBest, bool isToDelete, List<ImageMetadata> allInSet) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(selectionProvider.notifier).toggleSelection(img.path);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToDelete ? Colors.red : Colors.grey.shade200,
                width: isToDelete ? 3 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: Image.file(File(img.path), fit: BoxFit.cover, cacheWidth: 400)),
                if (isBest) 
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.orange.shade50,
                    child: const Text("BEST", textAlign: TextAlign.center, style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 6, right: 6,
          child: Icon(
            isToDelete ? Icons.delete_forever : Icons.circle_outlined,
            color: isToDelete ? Colors.red : Colors.white70,
            size: 20,
            shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
        Positioned(
          bottom: 35, right: 6,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (context) => FullScreenImageViewer(images: allInSet, initialIndex: allInSet.indexOf(img)),
            )),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.fullscreen, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction(BuildContext context, WidgetRef ref, List results, Set<String> selectedPaths, String folderPath) {
    int totalImages = results.fold(0, (sum, set) => sum + (set.images.length as int));
    int deleteCount = selectedPaths.length;
    int keepCount = totalImages - deleteCount;
    double savedMB = 0;
    for (var set in results) {
      for (var img in set.images) { if (selectedPaths.contains(img.path)) savedMB += img.sizeInMB; }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: const Offset(0, -10))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$keepCount장 보관 / $deleteCount장 선택됨", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text("예상 확보 용량: ${savedMB.toStringAsFixed(1)} MB", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: deleteCount == 0 ? null : () => _showProcessOptions(context, ref, results, selectedPaths, folderPath),
              icon: const Icon(Icons.auto_delete),
              label: const Text("정리 시작", style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProcessOptions(BuildContext context, WidgetRef ref, List results, Set<String> selectedPaths, String folderPath) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("어떻게 정리할까요?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.move_to_inbox)),
                title: const Text("다른 폴더로 이동 (권장)"),
                subtitle: const Text("'_duplicate' 폴더로 안전하게 옮깁니다."),
                onTap: () => _confirmAction(context, ref, results, selectedPaths, folderPath, 'MOVE'),
              ),
              ListTile(
                leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: const Icon(Icons.delete_forever, color: Colors.red)),
                title: const Text("영구 삭제", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                subtitle: const Text("파일이 기기에서 즉시 삭제되며 복구할 수 없습니다."),
                onTap: () => _confirmAction(context, ref, results, selectedPaths, folderPath, 'DELETE'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmAction(BuildContext context, WidgetRef ref, List results, Set<String> selectedPaths, String folderPath, String mode) {
    Navigator.pop(context);
    int deleteCount = selectedPaths.length;
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mode == 'DELETE' ? "영구 삭제" : "이동 확인"),
        content: Text("$deleteCount장의 사진을 ${mode == 'DELETE' ? '정말 삭제' : '이동'}하시겠습니까?\n이 작업은 되돌릴 수 없습니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          FilledButton(
            onPressed: () async {
              bool allSetsHaveAtLeastOneKept = true;
              for (var set in results) {
                if (set.images.every((img) => selectedPaths.contains(img.path))) {
                  allSetsHaveAtLeastOneKept = false; break;
                }
              }
              if (!allSetsHaveAtLeastOneKept) {
                showDialog(context: context, builder: (context) => AlertDialog(
                  title: const Text("주의"), content: const Text("모든 사진을 정리하려는 세트가 있습니다.\n최소 한 장은 유지해 주세요."),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인"))],
                ));
                return;
              }
              Navigator.pop(context);
              _startProcessing(navigator, results, selectedPaths, folderPath, mode);
            },
            style: mode == 'DELETE' ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  Future<void> _startProcessing(NavigatorState navigator, List results, Set<String> selectedPaths, String folderPath, String mode) async {
    final List<String> targetPaths = selectedPaths.toList();
    progressNotifier.value = 0.0;
    BuildContext? dialogContext;

    showDialog(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) {
        dialogContext = context;
        return AlertDialog(
          title: Text(mode == 'DELETE' ? "사진 삭제 중..." : "사진 이동 중..."),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: progressNotifier,
                builder: (context, value, child) {
                  return Column(children: [
                    LinearProgressIndicator(value: value),
                    const SizedBox(height: 8),
                    Text("${(value * 100).toInt()}% 완료"),
                  ]);
                },
              ),
            ],
          ),
        );
      },
    );

    try {
      await FileService.processFiles(
        targetPaths: targetPaths, originalFolderPath: folderPath, mode: mode,
        onProgress: (current, total) => progressNotifier.value = current / total,
      );
      ref.read(analysisProvider.notifier).clearResults();
      ref.read(selectionProvider.notifier).clear();
    } catch (_) {
    } finally {
      progressNotifier.value = 1.0;
      await Future.delayed(const Duration(milliseconds: 600));
      if (dialogContext != null && dialogContext!.mounted) Navigator.of(dialogContext!).pop();
      await Future.delayed(const Duration(milliseconds: 300));
      if (navigator.mounted) _showCleanupReport(navigator.context, targetPaths.length);
    }
  }

  void _showCleanupReport(BuildContext context, int count) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration, size: 80, color: Colors.orange),
            const SizedBox(height: 24),
            const Text("정리 완료!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("총 $count장의 사진을 정리했습니다.\n갤러리가 더 깔끔해졌어요!", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.popUntil(context, ModalRoute.withName('/')), child: const Text("확인"))),
          ],
        ),
      ),
    );
  }
}

class FullScreenImageViewer extends ConsumerStatefulWidget {
  final List<ImageMetadata> images;
  final int initialIndex;

  const FullScreenImageViewer({super.key, required this.images, required this.initialIndex});

  @override
  ConsumerState<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends ConsumerState<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late List<TransformationController> _controllers;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _controllers = List.generate(widget.images.length, (index) => TransformationController());
    
    for (var controller in _controllers) {
      controller.addListener(() {
        final matrix = controller.value;
        for (var other in _controllers) {
          if (other != controller) other.value = matrix;
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPaths = ref.watch(selectionProvider);
    final currentImage = widget.images[_currentIndex];
    final isToDelete = selectedPaths.contains(currentImage.path);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text("${_currentIndex + 1} / ${widget.images.length}", style: const TextStyle(color: Colors.white, fontSize: 16)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            physics: const NeverScrollableScrollPhysics(), // 스와이프 차단
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                transformationController: _controllers[index],
                minScale: 0.5, maxScale: 8.0,
                child: Center(child: Image.file(File(widget.images[index].path), fit: BoxFit.contain)),
              );
            },
          ),
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      int prevIndex = (_currentIndex - 1 + widget.images.length) % widget.images.length;
                      _pageController.jumpToPage(prevIndex);
                    },
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      int nextIndex = (_currentIndex + 1) % widget.images.length;
                      _pageController.jumpToPage(nextIndex);
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(selectionProvider.notifier).toggleSelection(currentImage.path);
                },
                icon: Icon(isToDelete ? Icons.delete_forever : Icons.check_circle_outline),
                label: Text(isToDelete ? "정리 대상으로 선택됨" : "이 사진 유지하기", style: const TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: isToDelete ? Colors.red : Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ),
          const Positioned(top: 20, right: 20, child: Icon(Icons.zoom_in, color: Colors.white54, size: 24)),
        ],
      ),
    );
  }
}

final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
