import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/analysis_provider.dart';
import '../services/permission_service.dart';
import '../services/update_service.dart';
import '../services/history_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _threshold = 50.0;
  bool _isAdvancedMode = false;
  String? _selectedPath;
  List<String> _recentFolders = [];
  int _estimatedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _loadHistory() async {
    final history = await HistoryService.getRecentFolders();
    setState(() => _recentFolders = history);
  }

  Future<void> _initApp() async {
    bool isGranted = await PermissionService.isStoragePermissionGranted();
    if (!isGranted && mounted) {
      await PermissionService.requestStoragePermission(context);
    }
    if (mounted) {
      await UpdateService.checkUpdate(context);
    }
  }

  Future<void> _pickFolder() async {
    bool granted = await PermissionService.isStoragePermissionGranted();
    if (!granted && mounted) {
      granted = await PermissionService.requestStoragePermission(context);
    }
    if (!granted) return;

    String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      _setFolderPath(path);
    }
  }

  void _setFolderPath(String path) {
    setState(() {
      _selectedPath = path;
      _estimatePhotos(path);
    });
  }

  Future<void> _estimatePhotos(String path) async {
    try {
      final dir = Directory(path);
      int count = 0;
      await for (var entity in dir.list()) {
        if (entity is File && entity.path.toLowerCase().contains(RegExp(r'\.(jpg|jpeg|png|heic)$'))) {
          count++;
        }
      }
      setState(() => _estimatedCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(analysisProvider);
    final bool hasSavedResults = analysisState.results.isNotEmpty && !analysisState.isAnalyzing;

    return Scaffold(
      appBar: AppBar(
        title: const Text("중복 사진 제거기"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update),
            onPressed: () => UpdateService.checkUpdate(context, showNoUpdateMsg: true),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasSavedResults) _buildContinueCard(analysisState),
            const SizedBox(height: 16),
            _buildSettingsCard(),
            const SizedBox(height: 24),
            if (_recentFolders.isNotEmpty) _buildRecentFolders(),
            const SizedBox(height: 24),
            _buildFolderInfo(),
            const SizedBox(height: 16),
            _buildFolderSelectionButton(),
            const SizedBox(height: 16),
            _buildStartButton(hasSavedResults),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueCard(AnalysisState state) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => Navigator.pushNamed(context, '/comparison', arguments: state.folderPath ?? ""),
        leading: const Icon(Icons.history_edu, color: Colors.blue),
        title: const Text("정리하던 작업이 있습니다", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${state.results.length}개의 중복 세트 이어하기"),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.tune, size: 20),
                const SizedBox(width: 8),
                const Text("검사 강도 설정", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Text(_threshold.toInt().toString(), 
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 20),
            if (!_isAdvancedMode)
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment<double>(value: 30.0, label: Text("엄격"), icon: Icon(Icons.copy, size: 16)),
                  ButtonSegment<double>(value: 50.0, label: Text("기본"), icon: Icon(Icons.auto_awesome_motion, size: 16)),
                  ButtonSegment<double>(value: 70.0, label: Text("유연"), icon: Icon(Icons.filter_vintage_outlined, size: 16)),
                ],
                selected: {_threshold},
                onSelectionChanged: (Set<double> newSelection) => setState(() => _threshold = newSelection.first),
                showSelectedIcon: false,
              )
            else
              Slider(
                value: _threshold, min: 30, max: 70, divisions: 40,
                label: _threshold.toInt().toString(),
                onChanged: (val) => setState(() => _threshold = val),
              ),
            const SizedBox(height: 16),
            _buildThresholdDescription(),
            const Divider(height: 32),
            SwitchListTile(
              title: const Text("고급 설정", style: TextStyle(fontSize: 14)),
              value: _isAdvancedMode,
              dense: true,
              onChanged: (val) => setState(() => _isAdvancedMode = val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdDescription() {
    String desc = "";
    int val = _threshold.toInt();
    if (val <= 35) desc = "완전히 똑같은 복사본 위주로 찾습니다.";
    else if (val <= 55) desc = "구도가 비슷한 연사 사진을 효과적으로 찾습니다.";
    else desc = "배경이 같은 유사한 사진까지 넓게 찾습니다.";
    return Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey));
  }

  Widget _buildRecentFolders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("최근 폴더", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 8),
        ..._recentFolders.take(3).map((path) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: InkWell(
            onTap: () => _setFolderPath(path),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(path, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildFolderInfo() {
    if (_selectedPath == null || _estimatedCount == 0) return const SizedBox.shrink();
    int estSeconds = (_estimatedCount * 0.05).toInt();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("사진 약 $_estimatedCount장 발견", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text("예상 소요 시간: 약 ${estSeconds < 1 ? 1 : estSeconds}초", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSelectionButton() {
    return OutlinedButton.icon(
      onPressed: _pickFolder,
      icon: const Icon(Icons.folder_open),
      label: Text(_selectedPath ?? "분석할 폴더 선택"),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildStartButton(bool hasSaved) {
    return FilledButton(
      onPressed: _selectedPath == null ? null : () async {
        if (hasSaved) {
          bool? startNew = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("새 분석 시작"),
              content: const Text("이전에 분석한 결과가 사라집니다. 새로 분석하시겠습니까?"),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("새로 분석")),
              ],
            ),
          );
          if (startNew != true) return;
        }
        await HistoryService.addFolder(_selectedPath!);
        ref.read(analysisProvider.notifier).startAnalysis(_selectedPath!, _threshold.toInt());
        if (mounted) Navigator.pushNamed(context, '/analysis', arguments: _selectedPath);
      },
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text("분석 시작", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
