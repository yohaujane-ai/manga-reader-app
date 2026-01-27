class MangaBook {
  final String path;
  final String name;
  int currentPage;
  int totalPages;
  DateTime lastRead;

  MangaBook({
    required this.path,
    required this.name,
    this.currentPage = 0,
    this.totalPages = 0,
    DateTime? lastRead,
  }) : lastRead = lastRead ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'lastRead': lastRead.toIso8601String(),
  };

  factory MangaBook.fromJson(Map<String, dynamic> json) => MangaBook(
    path: json['path'],
    name: json['name'],
    currentPage: json['currentPage'] ?? 0,
    totalPages: json['totalPages'] ?? 0,
    lastRead: json['lastRead'] != null 
        ? DateTime.parse(json['lastRead']) 
        : DateTime.now(),
  );
}
