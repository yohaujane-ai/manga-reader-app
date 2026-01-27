import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/bookshelf_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 设置状态栏透明
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  
  runApp(const MangaReaderApp());
}

class MangaReaderApp extends StatelessWidget {
  const MangaReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '漫画阅读器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1a1a1a),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2a2a2a),
          elevation: 0,
        ),
      ),
      home: const BookshelfScreen(),
    );
  }
}
