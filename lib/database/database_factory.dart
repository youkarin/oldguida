import 'database_factory_stub.dart'
    if (dart.library.html) 'database_factory_web.dart'
    if (dart.library.io) 'database_factory_io.dart';

Future<void> initDatabaseFactory() => initDatabaseFactoryImpl();
