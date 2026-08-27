class Platform {
  static const bool isWindows = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
}

class File {
  File(String path);
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) async {}
}

class Directory {
  Directory(this.path);

  final String path;

  Future<Directory> create({bool recursive = false}) async => this;
  Future<Directory> createTemp([String? prefix]) async => this;
  Future<bool> exists() async => false;
  Future<void> delete({bool recursive = false}) async {}
}
