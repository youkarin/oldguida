import 'dart:io';
import 'package:http/http.dart' as http;

class _SanitizingClient extends http.BaseClient {
  final http.Client _inner;
  _SanitizingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Strip any disallowed newline characters and non-ASCII bytes from all
    // header values to avoid `FormatException` when underlying platforms
    // expose localized OS strings (e.g. Chinese Windows versions).
    request.headers.updateAll((key, value) {
      var sanitized = value.replaceAll(RegExp(r'[\n\r]'), ' ');
      sanitized = sanitized.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
      return sanitized;
    });

    // Always provide a simple user agent to avoid platform strings like
    // "Windows 11" that may contain line breaks.
    request.headers[HttpHeaders.userAgentHeader] = 'italian_driving_app';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

http.Client createSanitizedClient() => _SanitizingClient(http.Client());
