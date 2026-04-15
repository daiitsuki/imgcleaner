import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/analysis_provider.dart';
import '../services/permission_service.dart';
import '../services/update_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  double _threshold = 5.0; // 기본 민감도 임계값
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    // 앱 시작 시 권한 체크 및 업데이트 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _initApp() async {
    // 1. 권한 체크
    bool isGranted = await PermissionService.isStoragePermissionGranted();
    if (!isGranted && mounted) {
      await PermissionService.requestStoragePermission(context);
    }
    
    // 2. 자동 업데이트 체크
    if (mounted) {
      await UpdateService.checkUpdate(context);
    }
  }

  Future<void> _pickFolder() async {
    // 권한 체크 먼저 수행
    bool granted = await PermissionService.isStoragePermissionGranted();
    if (!granted) {
      if (mounted) {
        granted = await PermissionService.requestStoragePermission(context);
      }
    }

    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("폴더 접근 및 파일 관리를 위해 권한 허용이 필요합니다.")),
        );
      }
      return;
    }

    String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      setState(() => _selectedPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("중복 사진 제거기"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: '업데이트 확인',
            onPressed: () => UpdateService.checkUpdate(context, showNoUpdateMsg: true),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSettingsCard(),
            const Spacer(),
            _buildFolderSelectionButton(),
            const SizedBox(height: 16),
            _buildStartButton(),
          ],
        ),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("유사도 민감도 (pHash)", 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("${_threshold.toInt()}", 
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: _threshold,
              min: 0, max: 20, divisions: 20,
              onChanged: (val) => setState(() => _threshold = val),
            ),
            const Text(
              "낮을수록 똑같은 사진 위주로 찾고, 높을수록 비슷한 사진들을 더 많이 찾습니다.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
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

  Widget _buildStartButton() {
    return FilledButton(
      onPressed: _selectedPath == null ? null : () {
        ref.read(analysisProvider.notifier).startAnalysis(
          _selectedPath!, 
          _threshold.toInt()
        );
        Navigator.pushNamed(context, '/analysis', arguments: _selectedPath);
      },
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text("분석 시작", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
