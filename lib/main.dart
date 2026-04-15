import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/comparison_screen.dart';

void main() {
  // 이미지 캐시 크기 대폭 확장
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 200; // 개수 제한 (기본 1000)
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024; // 100MB (기본 10MB)

  runApp(
    const ProviderScope(
      child: DuplicatePhotoCleanerApp(),
    ),
  );
}

class DuplicatePhotoCleanerApp extends StatelessWidget {
  const DuplicatePhotoCleanerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '중복 사진 제거기',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
      ),
      // 라우팅 설정
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/analysis': (context) => const AnalysisScreen(),
        '/comparison': (context) => const ComparisonScreen(),
      },
    );
  }
}
