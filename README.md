# 漫画阅读器 - Android 版

专为日漫设计的本地漫画阅读器，支持折叠屏双页显示。

## 功能

- 📚 书架管理：添加的漫画自动保存
- 📖 双页/单页切换：点击屏幕中央调出控制栏切换
- 🔄 从右到左翻页：符合日漫阅读习惯
- 💾 进度自动保存：关闭后再打开从上次位置继续
- 📱 折叠屏优化：展开时双页模式效果最佳

## 操作方式

### 阅读时（全屏无干扰）
- **点击左侧 1/3**：下一页
- **点击右侧 1/3**：上一页
- **点击中间**：显示/隐藏控制栏（5秒自动隐藏）
- **左滑**：下一页
- **右滑**：上一页

### 控制栏
- 进度条：拖动快速跳转
- 双页/单页按钮：切换显示模式
- 返回按钮：回到书架

---

## 打包方法（使用 Codemagic 在线打包）

### 步骤 1：上传代码到 GitHub

1. 登录你的 GitHub 账号
2. 新建一个仓库，比如叫 `manga-reader-app`
3. 把这个项目文件夹的所有文件上传上去

### 步骤 2：使用 Codemagic 打包

1. 打开 https://codemagic.io
2. 用 GitHub 账号登录
3. 点击 "Add application"
4. 选择你刚才创建的仓库
5. 选择 "Flutter App"
6. 在 Build settings 里：
   - Platform: Android
   - Build mode: Release
   - 取消勾选 "Code signing"（不签名也能安装）
7. 点击 "Start new build"
8. 等几分钟，打包完成后下载 APK

### 步骤 3：安装到手机

1. 把 APK 文件传到手机（微信/QQ/数据线都行）
2. 在手机上打开 APK
3. 允许"安装未知应用"
4. 完成安装

---

## 如果 Codemagic 不行，备选方案

### FlutterFlow 在线打包
1. https://app.flutterflow.io
2. 导入项目代码
3. 直接在网页上打包

### Appetize 在线模拟器（测试用）
1. https://appetize.io
2. 上传 APK 在浏览器里运行

---

## 项目结构

```
manga_app/
├── pubspec.yaml          # 依赖配置
├── lib/
│   ├── main.dart         # 入口
│   ├── models/
│   │   └── manga_book.dart    # 数据模型
│   ├── services/
│   │   └── storage_service.dart   # 本地存储
│   └── screens/
│       ├── bookshelf_screen.dart  # 书架页面
│       └── reader_screen.dart     # 阅读页面
└── android/
    └── app/src/main/
        └── AndroidManifest.xml    # Android 权限配置
```

## 注意事项

1. 首次打开需要授权存储权限
2. PDF 文件留在原位置，App 只记录路径
3. 如果文件被移动/删除，会自动从书架移除
