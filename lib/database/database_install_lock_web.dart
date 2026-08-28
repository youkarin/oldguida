import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<T> runWithDatabaseInstallLockImpl<T>(
  String name,
  Future<T> Function() action,
) async {
  final navigator = web.window.navigator;
  if (!(navigator as JSObject).has('locks')) {
    throw UnsupportedError(
      'Web Locks API is required for safe bundled database installation.',
    );
  }

  late T result;
  Object? actionError;
  StackTrace? actionStackTrace;

  Future<void> invokeAction() async {
    try {
      result = await action();
    } catch (error, stackTrace) {
      actionError = error;
      actionStackTrace = stackTrace;
    }
  }

  final callback = ((web.Lock _) => invokeAction().toJS).toJS;
  await navigator.locks
      .request(
        name,
        web.LockOptions(mode: 'exclusive'),
        callback,
      )
      .toDart;

  final error = actionError;
  if (error != null) {
    Error.throwWithStackTrace(error, actionStackTrace!);
  }
  return result;
}
