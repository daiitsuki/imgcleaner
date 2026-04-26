import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/analysis_provider.dart';
import '../providers/selection_provider.dart';
import '../services/permission_service.dart';
import '../services/update_service.dart';
import '../services/history_service.dart';

enum DateRangeOption {
  all("전체"),
  week("최근 1주"),
  month1("최근 1개월"),
  month3("최근 3개월"),
  custom("직접 선택");

  final String label;
  const DateRangeOption(this.label);
}

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

  DateRangeOption _dateRangeOption = DateRangeOption.all;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

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

      DateTime? startDate, endDate;
      final now = DateTime.now();
      switch (_dateRangeOption) {
        case DateRangeOption.all:
          break;
        case DateRangeOption.week:
          startDate = now.subtract(const Duration(days: 7));
          break;
        case DateRangeOption.month1:
          startDate = now.subtract(const Duration(days: 30));
          break;
        case DateRangeOption.month3:
          startDate = now.subtract(const Duration(days: 90));
          break;
        case DateRangeOption.custom:
          startDate = _customStartDate;
          endDate = _customEndDate;
          break;
      }

      await for (var entity in dir.list()) {
        if (entity is File &&
            entity.path
                .toLowerCase()
                .contains(RegExp(r'\.(jpg|jpeg|png|heic)$'))) {
          if (startDate != null || endDate != null) {
            final lastMod = await entity.lastModified();
            if (startDate != null && lastMod.isBefore(startDate)) continue;
            if (endDate != null && lastMod.isAfter(endDate)) continue;
          }
          count++;
        }
      }
      setState(() => _estimatedCount = count);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(analysisProvider);
    final bool hasSavedResults =
        analysisState.results.isNotEmpty && !analysisState.isAnalyzing;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("중복 사진 정리",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt_outlined),
            onPressed: () =>
                UpdateService.checkUpdate(context, showNoUpdateMsg: true),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasSavedResults) ...[
              _buildContinueCard(analysisState),
              const SizedBox(height: 20),
            ],
            _buildSectionTitle("검사 설정", Icons.settings_suggest_outlined),
            const SizedBox(height: 12),
            _buildSettingsCard(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                return Stack(
                  alignment: Alignment.topCenter,
                  children: <Widget>[
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(sizeFactor: animation, axisAlignment: -1.0, child: child),
                );
              },
              child: _isAdvancedMode 
                ? Column(
                    key: const ValueKey("advanced_mode_on"),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      _buildDateFilterCard(),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey("advanced_mode_off")),
            ),            const SizedBox(height: 32),
            if (_recentFolders.isNotEmpty) ...[
              _buildSectionTitle("최근 분석한 폴더", Icons.history),
              const SizedBox(height: 12),
              _buildRecentFolders(),
              const SizedBox(height: 32),
            ],
            _buildSectionTitle("분석 대상", Icons.folder_open_outlined),
            const SizedBox(height: 12),
            _buildFolderSelectionButton(),
            const SizedBox(height: 16),
            _buildFolderInfo(),
            const SizedBox(height: 40),
            _buildStartButton(hasSavedResults),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey)),
      ],
    );
  }

  Widget _buildContinueCard(AnalysisState state) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [Colors.blue.shade600, Colors.blue.shade400]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        onTap: () => Navigator.pushNamed(context, '/comparison',
            arguments: state.folderPath ?? ""),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: const CircleAvatar(
            backgroundColor: Colors.white24,
            child: Icon(Icons.play_arrow_rounded, color: Colors.white)),
        title: const Text("이전 작업 이어하기",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text("${state.results.length}개의 중복 세트가 기다리고 있어요",
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
          onPressed: () => _confirmDeleteSavedResults(context),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("검사 강도",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(height: 4),
                    Text("수치가 높을수록 더 많은 유사 사진을 찾습니다.",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12)),
                child: Text("${_threshold.toInt()}%",
                    style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!_isAdvancedMode)
            Row(
              children: [
                _buildSimpleThresholdBtn("엄격", 30.0),
                const SizedBox(width: 8),
                _buildSimpleThresholdBtn("기본", 50.0),
                const SizedBox(width: 8),
                _buildSimpleThresholdBtn("유연", 70.0),
              ],
            )
          else
            Slider(
              value: _threshold,
              min: 30,
              max: 70,
              divisions: 40,
              activeColor: Colors.blue,
              inactiveColor: Colors.blue.shade50,
              onChanged: (val) => setState(() => _threshold = val),
            ),
          const Divider(height: 40),
          SwitchListTile(
            title: const Text("고급 설정 모드",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle:
                const Text("기간 필터 및 상세 감도 조절", style: TextStyle(fontSize: 11)),
            value: _isAdvancedMode,
            contentPadding: EdgeInsets.zero,
            activeColor: Colors.blue,
            onChanged: (val) => setState(() => _isAdvancedMode = val),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleThresholdBtn(String label, double val) {
    bool isSelected = _threshold == val;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _threshold = val),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade200),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.black54,
              )),
        ),
      ),
    );
  }

  Widget _buildDateFilterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("분석 기간 설정",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DateRangeOption.values.map((opt) {
              bool isSelected = _dateRangeOption == opt;
              return ChoiceChip(
                label: Text(opt.label),
                selected: isSelected,
                onSelected: (selected) async {
                  if (selected) {
                    setState(() => _dateRangeOption = opt);
                    if (opt == DateRangeOption.custom) {
                      final picked = await _showYearMonthRangePicker();
                      if (picked != null) {
                        setState(() {
                          _customStartDate = picked.start;
                          _customEndDate = picked.end;
                        });
                      } else if (_customStartDate == null) {
                        setState(() => _dateRangeOption = DateRangeOption.all);
                      }
                    }
                    if (_selectedPath != null) _estimatePhotos(_selectedPath!);
                  }
                },
                selectedColor: Colors.blue.shade100,
                backgroundColor: Colors.grey.shade50,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.blue.shade700 : Colors.black54,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                side: BorderSide(
                    color: isSelected
                        ? Colors.blue.shade200
                        : Colors.grey.shade200),
                showCheckmark: false,
              );
            }).toList(),
          ),
          if (_dateRangeOption == DateRangeOption.custom &&
              _customStartDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  "📅 ${_customStartDate!.year}년 ${_customStartDate!.month}월 ~ ${_customEndDate!.year}년 ${_customEndDate!.month}월",
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<DateTimeRange?> _showYearMonthRangePicker() async {
    DateTime now = DateTime.now();
    DateTime start = _customStartDate ?? DateTime(now.year, now.month);
    DateTime end = _customEndDate ?? DateTime(now.year, now.month);

    return showDialog<DateTimeRange>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("기간 설정 (연-월)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isValid = !start.isAfter(end);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("시작 연-월",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                _buildYearMonthScrollPicker(
                  initialDate: start,
                  onChanged: (date) => setDialogState(() => start = date),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child:
                      Icon(Icons.arrow_downward, size: 16, color: Colors.blue),
                ),
                const Text("종료 연-월",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                _buildYearMonthScrollPicker(
                  initialDate: end,
                  onChanged: (date) => setDialogState(() => end = date),
                ),
                if (!isValid)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      "시작일이 종료일보다 늦을 수 없습니다.",
                      style: TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("취소")),
          StatefulBuilder(
            builder: (context, setDialogState) {
              // start와 end가 변할 때 isValid를 다시 계산해야 함
              // 하지만 부모 StatefulBuilder에서 이미 start/end를 관리하므로
              // 여기서는 그냥 current 값만 체크
              final bool isValid = !start.isAfter(end);
              return FilledButton(
                onPressed: isValid
                    ? () {
                        DateTime finalEnd =
                            DateTime(end.year, end.month + 1, 0, 23, 59, 59);
                        Navigator.pop(context,
                            DateTimeRange(start: start, end: finalEnd));
                      }
                    : null,
                child: const Text("설정 완료"),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildYearMonthScrollPicker(
      {required DateTime initialDate, required Function(DateTime) onChanged}) {
    final int currentYear = DateTime.now().year;
    final List<int> years = List.generate(25, (i) => currentYear - i);
    final List<int> months = List.generate(12, (i) => i + 1);

    return StatefulBuilder(builder: (context, setLocalState) {
      int selectedYear = initialDate.year;
      int selectedMonth = initialDate.month;

      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildScrollWheel(
                items: years.map((y) => "${y}년").toList(),
                initialIndex: years.indexOf(selectedYear),
                onChanged: (index) {
                  setLocalState(() => selectedYear = years[index]);
                  onChanged(DateTime(selectedYear, selectedMonth));
                },
              ),
            ),
            Container(width: 1, color: Colors.grey.shade200, height: 40),
            Expanded(
              child: _buildScrollWheel(
                items: months.map((m) => "${m}월").toList(),
                initialIndex: months.indexOf(selectedMonth),
                onChanged: (index) {
                  setLocalState(() => selectedMonth = months[index]);
                  onChanged(DateTime(selectedYear, selectedMonth));
                },
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildScrollWheel(
      {required List<String> items,
      required int initialIndex,
      required Function(int) onChanged}) {
    int selectedIdx = initialIndex;

    return StatefulBuilder(builder: (context, setLocalState) {
      return ListWheelScrollView.useDelegate(
        itemExtent: 35,
        physics: const FixedExtentScrollPhysics(),
        controller: FixedExtentScrollController(
            initialItem: initialIndex != -1 ? initialIndex : 0),
        useMagnifier: true,
        magnification: 1.2,
        onSelectedItemChanged: (index) {
          setLocalState(() => selectedIdx = index);
          onChanged(index);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: items.length,
          builder: (context, index) {
            final isSelected = selectedIdx == index;
            return Center(
              child: Text(
                items[index],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.blue.shade700 : Colors.black45,
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildRecentFolders() {
    return Column(
      children: _recentFolders
          .take(3)
          .map((path) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade100)),
                child: ListTile(
                  onTap: () => _setFolderPath(path),
                  leading:
                      const Icon(Icons.folder, size: 20, color: Colors.amber),
                  title: Text(path.split(Platform.pathSeparator).last,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(path,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right,
                      size: 16, color: Colors.grey),
                  dense: true,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildFolderSelectionButton() {
    return InkWell(
      onTap: _pickFolder,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.blue.shade100, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.blue.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            Icon(Icons.photo_library_rounded, size: 32, color: Colors.blue.shade400),
            const SizedBox(height: 12),
            Text(_selectedPath ?? "분석할 폴더를 선택해주세요", style: TextStyle(
                  fontSize: 15,
                  fontWeight: _selectedPath != null
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: _selectedPath != null ? Colors.black87 : Colors.grey,
                ),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderInfo() {
    if (_selectedPath == null) return const SizedBox.shrink();

    if (_estimatedCount == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 20, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _dateRangeOption == DateRangeOption.all
                    ? "선택한 폴더에 분석 가능한 사진이 없습니다."
                    : "선택한 기간 내에 분석 가능한 사진이 없습니다.",
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.red),
              ),
            ),
          ],
        ),
      );
    }

    int estSeconds = (_estimatedCount * 0.05).toInt();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("사진 약 $_estimatedCount장 발견",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.blue)),
              Text("예상 소요 시간: 약 ${estSeconds < 1 ? 1 : estSeconds}초",
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade300)),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSavedResults(BuildContext context) async {
    bool? delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("작업 삭제"),
        content: const Text("저장된 분석 결과와 선택 내역이 모두 삭제됩니다. 정말 삭제하시겠습니까?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("취소")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("삭제"),
          ),
        ],
      ),
    );

    if (delete == true) {
      ref.read(analysisProvider.notifier).clearResults();
      ref.read(selectionProvider.notifier).clear();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("저장된 작업이 삭제되었습니다.")));
    }
  }

  Widget _buildStartButton(bool hasSaved) {
    bool isDisabled = _selectedPath == null || _estimatedCount == 0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                    color: Colors.blue.withOpacity(0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 8))
              ],
      ),
      child: ElevatedButton(
        onPressed: isDisabled
            ? null
            : () async {
                if (hasSaved) {
                  bool? startNew = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
                      title: const Text("새 분석 시작"),
                      content: const Text("이전에 분석한 결과가 사라집니다. 새로 분석하시겠습니까?"),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("취소")),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("새로 분석")),
                      ],
                    ),
                  );
                  if (startNew != true) return;
                  ref.read(selectionProvider.notifier).clear();
                }

                DateTime? startDate, endDate;
                final now = DateTime.now();
                switch (_dateRangeOption) {
                  case DateRangeOption.all:
                    break;
                  case DateRangeOption.week:
                    startDate = now.subtract(const Duration(days: 7));
                    break;
                  case DateRangeOption.month1:
                    startDate = now.subtract(const Duration(days: 30));
                    break;
                  case DateRangeOption.month3:
                    startDate = now.subtract(const Duration(days: 90));
                    break;
                  case DateRangeOption.custom:
                    startDate = _customStartDate;
                    endDate = _customEndDate;
                    break;
                }

                await HistoryService.addFolder(_selectedPath!);
                ref.read(analysisProvider.notifier).startAnalysis(
                      _selectedPath!,
                      _threshold.toInt(),
                      startDate: startDate,
                      endDate: endDate,
                    );
                if (mounted)
                  Navigator.pushNamed(context, '/analysis',
                      arguments: _selectedPath);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: const Text("중복 사진 분석 시작",
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5)),
      ),
    );
  }
}
