import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/app.dart';
import 'package:terrenos/app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = await bootstrap();
  runApp(ProviderScope(overrides: overrides, child: const TerrenosApp()));
}
