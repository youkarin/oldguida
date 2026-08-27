import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:italian_driving_app/database/database_factory.dart';
import 'package:italian_driving_app/Services/keyword_translation_settings.dart';
import 'package:italian_driving_app/utils/http_overrides_stub.dart'
    if (dart.library.io) 'package:italian_driving_app/utils/http_overrides_io.dart';
import 'package:italian_driving_app/utils/sanitizing_client_stub.dart'
    if (dart.library.io) 'package:italian_driving_app/utils/sanitizing_client_io.dart';
import 'Screen/Homepage.dart';
import 'utils/debug_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await KeywordTranslationSettings.instance.load();

  applyHttpOverrides();

  await initDatabaseFactory();

  // 初始化 Supabase（替换成你的项目参数）
  await Supabase.initialize(
    url: 'https://johmstxkvvdfjdaxsgkm.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpvaG1zdHhrdnZkZmpkYXhzZ2ttIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTUwMjgsImV4cCI6MjA3MDU5MTAyOH0._qYTLZ23qE1q1UBlis68BjZurDbyTgKnVrQ5FOL2zQ4',
    httpClient: createSanitizedClient(),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OldGuida',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          primary: Colors.teal[400]!,
          secondary: Colors.tealAccent[700]!,
          surface: Colors.white,
          background: const Color(0xFFF0F4F4),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.teal[300],
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      scaffoldMessengerKey: DebugUtils.messengerKey,
      home: const HomePage(),
    );
  }
}
