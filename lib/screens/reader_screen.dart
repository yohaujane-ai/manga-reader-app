import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import '../models/manga_book.dart';
import '../services/storage_service.dart';

class ReaderScreen extends StatefulWidget {
  final MangaBook book;

  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  PdfDocument? _document;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoading = true;
  bool _showControls = false;
  bool _dualPage = true;
  Timer? _hideTimer;
  
  // 页面图片缓存
  final Map<int, PdfPageImage?> _pageCache = {};
  
  // 当前显示的图片
  PdfPageImage? _leftPageImage;
  PdfPageImage? _rightPageImage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPdf();
    _enterFullScreen();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _document?.close();
    _exitFullScreen();
    super.dispose();
  }

  void _enterFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _loadSettings() async {
    final settings = await StorageService.loadSettings();
    setState(() {
      _dualPage = settings['dualPage'] ?? true;
    });
  }

  Future<void> _loadPdf() async {
    try {
      _document = await PdfDocument.openFile(widget.book.path);
      _totalPages = _document!.pagesCount;
      _currentPage = widget.book.currentPage;
      
      // 确保页码有效
      if (_currentPage >= _totalPages) _currentPage = 0;
      
      // 更新书籍信息
      widget.book.totalPages = _totalPages;
      widget.book.currentPage = _currentPage;
      await StorageService.saveBooks(await StorageService.loadBooks().then((books) {
        final index = books.indexWhere((b) => b.path == widget.book.path);
        if (index >= 0) {
          books[index] = widget.book;
        }
        return books;
      }));
      
      setState(() {
        _isLoading = false;
      });
      
      await _renderCurrentPages();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开文件: $e')),
        );
      }
    }
  }

  Future<PdfPageImage?> _getPageImage(int pageNum) async {
    if (pageNum < 0 || pageNum >= _totalPages) return null;
    
    // 检查缓存
    if (_pageCache.containsKey(pageNum)) {
      return _pageCache[pageNum];
    }
    
    try {
      final page = await _document!.getPage(pageNum + 1); // pdfx 是 1-indexed
      final image = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.jpeg,
        quality: 90,
      );
      await page.close();
      
      // 缓存管理：最多保留10页
      if (_pageCache.length > 10) {
        final keysToRemove = _pageCache.keys
            .where((k) => (k - _currentPage).abs() > 5)
            .toList();
        for (final key in keysToRemove) {
          _pageCache.remove(key);
        }
      }
      
      _pageCache[pageNum] = image;
      return image;
    } catch (e) {
      return null;
    }
  }

  Future<void> _renderCurrentPages() async {
    if (_document == null) return;
    
    if (_dualPage) {
      // 双页模式：右边当前页，左边下一页
      final rightImage = await _getPageImage(_currentPage);
      final leftImage = await _getPageImage(_currentPage + 1);
      
      if (mounted) {
        setState(() {
          _rightPageImage = rightImage;
          _leftPageImage = leftImage;
        });
      }
    } else {
      // 单页模式
      final image = await _getPageImage(_currentPage);
      if (mounted) {
        setState(() {
          _rightPageImage = image;
          _leftPageImage = null;
        });
      }
    }
    
    // 预加载前后页
    _preloadPages();
  }

  void _preloadPages() {
    final step = _dualPage ? 2 : 1;
    // 预加载下两页
    _getPageImage(_currentPage + step);
    _getPageImage(_currentPage + step + 1);
    // 预加载上两页
    _getPageImage(_currentPage - step);
    _getPageImage(_currentPage - step - 1);
  }

  void _nextPage() {
    final step = _dualPage ? 2 : 1;
    if (_currentPage + step < _totalPages) {
      setState(() {
        _currentPage += step;
      });
      _saveProgress();
      _renderCurrentPages();
    }
  }

  void _prevPage() {
    final step = _dualPage ? 2 : 1;
    if (_currentPage - step >= 0) {
      setState(() {
        _currentPage -= step;
      });
    } else {
      setState(() {
        _currentPage = 0;
      });
    }
    _saveProgress();
    _renderCurrentPages();
  }

  void _goToPage(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() {
        _currentPage = page;
      });
      _saveProgress();
      _renderCurrentPages();
    }
  }

  Future<void> _saveProgress() async {
    widget.book.currentPage = _currentPage;
    await StorageService.updateBookProgress(widget.book.path, _currentPage);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    
    _hideTimer?.cancel();
    if (_showControls) {
      _hideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleDualPage() {
    setState(() {
      _dualPage = !_dualPage;
    });
    StorageService.saveSettings({'dualPage': _dualPage});
    _renderCurrentPages();
  }

  void _handleTap(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    
    if (x < width / 3) {
      // 左侧 1/3：下一页（日漫从右到左读）
      _nextPage();
    } else if (x > width * 2 / 3) {
      // 右侧 1/3：上一页
      _prevPage();
    } else {
      // 中间 1/3：显示/隐藏控制栏
      _toggleControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 漫画内容
                GestureDetector(
                  onTapUp: _handleTap,
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity! > 0) {
                      _nextPage(); // 从左往右拖：下一页
                    } else if (details.primaryVelocity! < 0) {
                      _prevPage(); // 从右往左拖：上一页
                    }
                  },
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: _buildPageView(),
                    ),
                  ),
                ),
                
                // 控制栏
                if (_showControls) _buildControlBar(),
              ],
            ),
    );
  }

  Widget _buildPageView() {
    if (_dualPage && _leftPageImage != null && _rightPageImage != null) {
      // 双页模式
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 左边：下一页
          Flexible(
            child: _buildPageImage(_leftPageImage),
          ),
          const SizedBox(width: 2),
          // 右边：当前页
          Flexible(
            child: _buildPageImage(_rightPageImage),
          ),
        ],
      );
    } else if (_rightPageImage != null) {
      // 单页模式或只有一页
      return _buildPageImage(_rightPageImage);
    } else {
      return const Center(
        child: Text('加载中...', style: TextStyle(color: Colors.white54)),
      );
    }
  }

  Widget _buildPageImage(PdfPageImage? image) {
    if (image == null) {
      return const SizedBox.shrink();
    }
    return Image.memory(
      image.bytes,
      fit: BoxFit.contain,
    );
  }

  Widget _buildControlBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.0),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部按钮行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 返回按钮
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    label: const Text('返回', 
                        style: TextStyle(color: Colors.white)),
                  ),
                  
                  // 书名
                  Expanded(
                    child: Text(
                      widget.book.name,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  
                  // 双页切换按钮
                  TextButton.icon(
                    onPressed: _toggleDualPage,
                    icon: Icon(
                      _dualPage ? Icons.menu_book : Icons.article,
                      color: _dualPage ? Colors.blue : Colors.white,
                    ),
                    label: Text(
                      _dualPage ? '双页' : '单页',
                      style: TextStyle(
                        color: _dualPage ? Colors.blue : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // 进度条
              Row(
                children: [
                  Text(
                    '${_currentPage + 1}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Expanded(
                    child: Slider(
                      value: _currentPage.toDouble(),
                      min: 0,
                      max: (_totalPages - 1).toDouble(),
                      onChanged: (value) {
                        _goToPage(value.toInt());
                      },
                      activeColor: Colors.blue,
                      inactiveColor: Colors.grey[700],
                    ),
                  ),
                  Text(
                    '$_totalPages',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
