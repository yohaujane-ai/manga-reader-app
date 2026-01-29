import 'dart:async';
import 'dart:math' as math;
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

class _ReaderScreenState extends State<ReaderScreen> with SingleTickerProviderStateMixin {
  PdfDocument? _document;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoading = true;
  bool _showControls = false;
  bool _dualPage = true;
  int _pageOffset = 0; // 跨页偏移：0=正常(1-2,3-4), 1=偏移(1单独,2-3,4-5)
  Timer? _hideTimer;
  
  // 翻页动画
  late AnimationController _pageAnimController;
  Animation<double>? _pageAnimation;
  bool _isAnimating = false;
  bool _animatingForward = true; // true=下一页, false=上一页
  
  // 页面图片缓存
  final Map<int, PdfPageImage?> _pageCache = {};
  
  // 当前显示的图片
  PdfPageImage? _leftPageImage;
  PdfPageImage? _rightPageImage;
  
  // 动画前的图片（用于翻页效果）
  PdfPageImage? _prevLeftImage;
  PdfPageImage? _prevRightImage;

  @override
  void initState() {
    super.initState();
    _pageAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _pageAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isAnimating = false;
        });
      }
    });
    _loadSettings();
    _loadPdf();
    _enterFullScreen();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pageAnimController.dispose();
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
      _pageOffset = settings['pageOffset'] ?? 0;
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

  // 根据跨页设置计算实际显示的页码
  List<int> _getDisplayPages(int basePage) {
    if (!_dualPage) {
      return [basePage];
    }
    
    // 考虑跨页偏移
    int adjustedPage = basePage;
    
    if (_pageOffset == 1) {
      // 偏移模式：第一页单独，之后成对
      if (basePage == 0) {
        return [0]; // 第一页单独显示
      }
      // 确保从偏移后的偶数页开始
      adjustedPage = basePage;
      if ((adjustedPage - 1) % 2 == 1) {
        adjustedPage -= 1;
      }
    } else {
      // 正常模式：0-1, 2-3, 4-5...
      if (basePage % 2 == 1) {
        adjustedPage = basePage - 1;
      }
    }
    
    List<int> pages = [adjustedPage];
    if (adjustedPage + 1 < _totalPages) {
      if (_pageOffset == 1 && adjustedPage == 0) {
        // 偏移模式第一页不加第二页
      } else {
        pages.add(adjustedPage + 1);
      }
    }
    
    return pages;
  }

  Future<void> _renderCurrentPages() async {
    if (_document == null) return;
    
    List<int> displayPages = _getDisplayPages(_currentPage);
    
    if (displayPages.length == 1) {
      // 单页模式或偏移模式的第一页
      final image = await _getPageImage(displayPages[0]);
      if (mounted) {
        setState(() {
          _rightPageImage = image;
          _leftPageImage = null;
        });
      }
    } else {
      // 双页模式：右边是当前页，左边是下一页
      final rightImage = await _getPageImage(displayPages[0]);
      final leftImage = await _getPageImage(displayPages[1]);
      
      if (mounted) {
        setState(() {
          _rightPageImage = rightImage;
          _leftPageImage = leftImage;
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
    if (_isAnimating) return;
    
    int step;
    if (!_dualPage) {
      step = 1;
    } else if (_pageOffset == 1 && _currentPage == 0) {
      step = 1; // 偏移模式第一页只跳1页
    } else {
      step = 2;
    }
    
    if (_currentPage + step < _totalPages) {
      // 保存当前图片用于动画
      _prevLeftImage = _leftPageImage;
      _prevRightImage = _rightPageImage;
      
      setState(() {
        _isAnimating = true;
        _animatingForward = true;
        _currentPage += step;
      });
      
      _pageAnimController.reset();
      _pageAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _pageAnimController, curve: Curves.easeInOut)
      );
      _pageAnimController.forward();
      
      _saveProgress();
      _renderCurrentPages();
    }
  }

  void _prevPage() {
    if (_isAnimating) return;
    
    int step;
    if (!_dualPage) {
      step = 1;
    } else if (_pageOffset == 1 && _currentPage <= 2) {
      step = _currentPage == 1 ? 1 : (_currentPage > 0 ? _currentPage : 0);
    } else {
      step = 2;
    }
    
    if (_currentPage - step >= 0) {
      _prevLeftImage = _leftPageImage;
      _prevRightImage = _rightPageImage;
      
      setState(() {
        _isAnimating = true;
        _animatingForward = false;
        _currentPage -= step;
      });
      
      _pageAnimController.reset();
      _pageAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _pageAnimController, curve: Curves.easeInOut)
      );
      _pageAnimController.forward();
      
      _saveProgress();
      _renderCurrentPages();
    } else if (_currentPage > 0) {
      _prevLeftImage = _leftPageImage;
      _prevRightImage = _rightPageImage;
      
      setState(() {
        _isAnimating = true;
        _animatingForward = false;
        _currentPage = 0;
      });
      
      _pageAnimController.reset();
      _pageAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _pageAnimController, curve: Curves.easeInOut)
      );
      _pageAnimController.forward();
      
      _saveProgress();
      _renderCurrentPages();
    }
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
    StorageService.saveSettings({'dualPage': _dualPage, 'pageOffset': _pageOffset});
    _renderCurrentPages();
  }

  void _togglePageOffset() {
    setState(() {
      _pageOffset = (_pageOffset + 1) % 2;
    });
    StorageService.saveSettings({'dualPage': _dualPage, 'pageOffset': _pageOffset});
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
    if (_isAnimating && _pageAnimation != null) {
      return AnimatedBuilder(
        animation: _pageAnimation!,
        builder: (context, child) {
          return _buildAnimatedPage(_pageAnimation!.value);
        },
      );
    }
    
    return _buildStaticPage();
  }

  Widget _buildStaticPage() {
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

  Widget _buildAnimatedPage(double value) {
    // 翻书动画效果
    if (_animatingForward) {
      // 向前翻页（下一页）- 从右向左翻
      return Stack(
        children: [
          // 新页面（目标页）
          _buildStaticPage(),
          // 旧页面（翻走的页）
          if (_prevRightImage != null)
            Positioned.fill(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1.0 - value,
                  child: Transform(
                    alignment: Alignment.centerRight,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(-value * math.pi / 2),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3 * (1 - value)),
                            blurRadius: 10,
                            offset: const Offset(-5, 0),
                          ),
                        ],
                      ),
                      child: _dualPage && _prevLeftImage != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: _buildPageImage(_prevLeftImage)),
                                const SizedBox(width: 2),
                                Flexible(child: _buildPageImage(_prevRightImage)),
                              ],
                            )
                          : _buildPageImage(_prevRightImage),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      // 向后翻页（上一页）- 从左向右翻
      return Stack(
        children: [
          // 新页面（目标页）
          _buildStaticPage(),
          // 旧页面（翻走的页）
          if (_prevRightImage != null)
            Positioned.fill(
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1.0 - value,
                  child: Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(value * math.pi / 2),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3 * (1 - value)),
                            blurRadius: 10,
                            offset: const Offset(5, 0),
                          ),
                        ],
                      ),
                      child: _dualPage && _prevLeftImage != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: _buildPageImage(_prevLeftImage)),
                                const SizedBox(width: 2),
                                Flexible(child: _buildPageImage(_prevRightImage)),
                              ],
                            )
                          : _buildPageImage(_prevRightImage),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
                  
                  // 跨页设置按钮（仅双页模式显示）
                  if (_dualPage)
                    TextButton.icon(
                      onPressed: _togglePageOffset,
                      icon: Icon(
                        Icons.swap_horiz,
                        color: _pageOffset == 1 ? Colors.orange : Colors.white,
                      ),
                      label: Text(
                        _pageOffset == 0 ? '跨页:标准' : '跨页:偏移',
                        style: TextStyle(
                          color: _pageOffset == 1 ? Colors.orange : Colors.white,
                          fontSize: 12,
                        ),
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
