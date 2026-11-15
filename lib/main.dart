import 'package:flutter/material.dart';

import 'backend/backend.dart';
import 'screens/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(YtdlApp(backend: createBackend()));
}

class YtdlApp extends StatelessWidget {
  const YtdlApp({super.key, required this.backend});

  final Backend backend;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFFD32F2F),
          brightness: b,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        );
    return MaterialApp(
      title: 'YTDL',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: AppShell(backend: backend),
    );
  }
}
