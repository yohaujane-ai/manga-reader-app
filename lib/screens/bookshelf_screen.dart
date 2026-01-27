import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/manga_book.dart';
import '../services/storage_service.dart';
import 'reader_screen.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  List<MangaBook> books = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final loadedBooks = await StorageService.loadBooks();
    
    // 过滤掉不存在的文件
    final validBooks = <MangaBook>[];
    for (final book in loadedBooks) {
      if (await File(book.path).exists()) {
        validBooks.add(book);
      }
    }
    
    // 按最近阅读排序
    validBooks.sort((a, b) => b.lastRead.compareTo(a.lastRead));
    
    setState(() {
      books = validBooks;
      isLoading = false;
    });
    
    // 如果有变化，保存
    if (validBooks.length != loadedBooks.length) {
      await StorageService.saveBooks(validBooks);
    }
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  Future<void> _pickFile() async {
    await _requestPermission();
    
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path!;
      final name = result.files.first.name.replaceAll('.pdf', '');
      
      // 检查是否已存在
      final existingIndex = books.indexWhere((b) => b.path == path);
      
      if (existingIndex >= 0) {
        // 已存在，直接打开
        _openBook(books[existingIndex]);
      } else {
        // 新书，添加到列表
        final newBook = MangaBook(path: path, name: name);
        setState(() {
          books.insert(0, newBook);
        });
        await StorageService.saveBooks(books);
        _openBook(newBook);
      }
    }
  }

  void _openBook(MangaBook book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(book: book),
      ),
    ).then((_) => _loadBooks()); // 返回时刷新列表
  }

  void _deleteBook(MangaBook book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text('删除确认', style: TextStyle(color: Colors.white)),
        content: Text('确定要从书架移除「${book.name}」吗？\n（不会删除原文件）',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                books.remove(book);
              });
              await StorageService.saveBooks(books);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📚 我的书架', 
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickFile,
            tooltip: '添加漫画',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : books.isEmpty
              ? _buildEmptyState()
              : _buildBookList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFile,
        icon: const Icon(Icons.folder_open),
        label: const Text('打开PDF'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book, size: 80, color: Colors.grey[600]),
          const SizedBox(height: 16),
          Text('书架是空的', 
              style: TextStyle(fontSize: 18, color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('点击下方按钮添加漫画', 
              style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildBookList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final progress = book.totalPages > 0 
            ? '${book.currentPage + 1} / ${book.totalPages}'
            : '未读';
        
        return Card(
          color: const Color(0xFF2a2a2a),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.book, color: Colors.white54),
            ),
            title: Text(book.name, 
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(progress,
                style: TextStyle(color: Colors.grey[500])),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () => _deleteBook(book),
            ),
            onTap: () => _openBook(book),
          ),
        );
      },
    );
  }
}
