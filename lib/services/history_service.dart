import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  static const String _key = 'recent_folders';

  static Future<List<String>> getRecentFolders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> addFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> folders = prefs.getStringList(_key) ?? [];
    
    // 중복 제거 및 최신화
    folders.remove(path);
    folders.insert(0, path);
    
    // 최근 5개만 유지
    if (folders.length > 5) {
      folders = folders.sublist(0, 5);
    }
    
    await prefs.setStringList(_key, folders);
  }

  static Future<void> removeFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> folders = prefs.getStringList(_key) ?? [];
    folders.remove(path);
    await prefs.setStringList(_key, folders);
  }
}
