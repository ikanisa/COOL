import 'package:hive_flutter/hive_flutter.dart';

typedef OpenHiveBox<T> = Future<Box<T>> Function(String name);
typedef InitializeHive = Future<void> Function();

Future<void> initializeHiveRuntime() => Hive.initFlutter();

Future<Box<T>> openHiveBox<T>(String name) => Hive.openBox<T>(name);
