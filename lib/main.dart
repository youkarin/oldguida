import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:italian_driving_app/database/database_factory.dart';
import 'package:italian_driving_app/utils/http_overrides_stub.dart'
    if (dart.library.io)
        'package:italian_driving_app/utils/http_overrides_io.dart';
import 'package:italian_driving_app/utils/sanitizing_client_stub.dart'
    if (dart.library.io)
        'package:italian_driving_app/utils/sanitizing_client_io.dart';
import 'Screen/Homepage.dart';
import 'utils/debug_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  applyHttpOverrides();

  await initDatabaseFactory();

  // 初始化 Supabase（替换成你的项目参数）
  await Supabase.initialize(
    url: 'https://johmstxkvvdfjdaxsgkm.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpvaG1zdHhrdnZkZmpkYXhzZ2ttIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTUwMTUwMjgsImV4cCI6MjA3MDU5MTAyOH0._qYTLZ23qE1q1UBlis68BjZurDbyTgKnVrQ5FOL2zQ4',
    httpClient: createSanitizedClient(),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'SF Pro Display'),
      scaffoldMessengerKey: DebugUtils.messengerKey,
      // 这里直接进入你的主页（你自己的会员逻辑在 Homepage 里处理）
      home: const HomePage(),
    );
  }
}
