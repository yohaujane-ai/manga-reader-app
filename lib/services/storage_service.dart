import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manga_book.dart';

class StorageService {
  static const String _booksKey = 'manga_books';
  static const String _settingsKey = 'settings';

  // 保存书籍列表
  static Future<void> saveBooks(List<MangaBook> books) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = books.map((b) => b.toJson()).toList();
    await prefs.setString(_booksKey, jsonEncode(jsonList));
  }

  // 加载书籍列表
  static Future<List<MangaBook>> loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_booksKey);
    if (jsonStr == null) return [];
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      return jsonList.map((j) => MangaBook.fromJson(j)).toList();
    } catch (e) {
      return [];
    }
  }

  // 更新单本书的进度
  static Future<void> updateBookProgress(String path, int page) async {
    final books = await loadBooks();
    final index = books.indexWhere((b) => b.path == path);
    if (index >= 0) {
      books[index].currentPage = page;
      books[index].lastRead = DateTime.now();
      await saveBooks(books);
    }
  }

  // 保存设置
  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings));
  }

  // 加载设置
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_settingsKey);
    if (jsonStr == null) {
      return {'dualPage': true};
    }
    try {
      return Map<String, dynamic>.from(jsonDecode(jsonStr));
    } catch (e) {
      return {'dualPage': true};
    }
  }
}
