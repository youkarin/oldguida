Future<T> runWithDatabaseInstallLockImpl<T>(
  String name,
  Future<T> Function() action,
) =>
    Future<T>.error(
      UnsupportedError(
        'Web Locks API is required for safe bundled database installation.',
      ),
    );
