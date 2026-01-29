import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
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
  
  // 封面缓存
  final Map<String, Uint8List> _coverCache = {};

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
    
    // 加载封面
    _loadCovers();
  }

  Future<void> _loadCovers() async {
    for (final book in books) {
      if (!_coverCache.containsKey(book.path)) {
        final cover = await _getCover(book.path);
        if (cover != null && mounted) {
          setState(() {
            _coverCache[book.path] = cover;
          });
        }
      }
    }
  }

  Future<Uint8List?> _getCover(String pdfPath) async {
    try {
      // 先检查缓存文件
      final cacheDir = await getApplicationDocumentsDirectory();
      final fileName = pdfPath.hashCode.toString();
      final cacheFile = File('${cacheDir.path}/covers/$fileName.jpg');
      
      if (await cacheFile.exists()) {
        return await cacheFile.readAsBytes();
      }
      
      // 生成封面
      final document = await PdfDocument.openFile(pdfPath);
      final page = await document.getPage(1);
      final image = await page.render(
        width: page.width * 0.5,
        height: page.height * 0.5,
        format: PdfPageImageFormat.jpeg,
        quality: 80,
      );
      await page.close();
      await document.close();
      
      // 保存到缓存
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsBytes(image!.bytes);
      
      return image.bytes;
    } catch (e) {
      return null;
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
        
        // 加载封面
        final cover = await _getCover(path);
        if (cover != null && mounted) {
          setState(() {
            _coverCache[path] = cover;
          });
        }
        
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
                _coverCache.remove(book.path);
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
              : _buildBookGrid(),
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

  Widget _buildBookGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final cover = _coverCache[book.path];
        final progress = book.totalPages > 0 
            ? '${book.currentPage + 1}/${book.totalPages}'
            : '';
        
        return GestureDetector(
          onTap: () => _openBook(book),
          onLongPress: () => _deleteBook(book),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 封面
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 5,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 封面图片
                      if (cover != null)
                        Image.memory(
                          cover,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(Icons.book, 
                                size: 40, color: Colors.white30),
                          ),
                        ),
                      
                      // 进度标签
                      if (progress.isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withOpacity(0.8),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            child: Text(
                              progress,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 6),
              
              // 书名
              Text(
                book.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}
