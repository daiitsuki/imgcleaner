import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 사용자가 '유지'하기로 선택한 파일들의 경로 리스트를 관리
class SelectionNotifier extends StateNotifier<Set<String>> {
  SelectionNotifier() : super({});

  void toggleSelection(String path) {
    if (state.contains(path)) {
      state = {...state}..remove(path);
    } else {
      state = {...state, path};
    }
  }

  void selectAll(List<String> paths) {
    state = {...state, ...paths};
  }

  void deselectAll(List<String> paths) {
    state = {...state}..removeAll(paths);
  }

  void clear() {
    state = {};
  }
}

final selectionProvider = StateNotifierProvider<SelectionNotifier, Set<String>>((ref) {
  return SelectionNotifier();
});
