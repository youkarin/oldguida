class File {
  File(String path);
  Future<void> writeAsBytes(List<int> bytes, {bool flush = false}) async {}
}

class Directory {
  Directory(String path);
  Future<Directory> create({bool recursive = false}) async => this;
}
