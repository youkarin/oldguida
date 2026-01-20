import 'dart:io';

class SaneHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.userAgent = 'italian_driving_app';
    return client;
  }
}

void applyHttpOverrides() {
  HttpOverrides.global = SaneHttpOverrides();
}
