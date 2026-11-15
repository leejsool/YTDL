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
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final scheme =
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6743D6),
            brightness: brightness,
          ).copyWith(
            primary: dark ? const Color(0xFFBDA9FF) : const Color(0xFF6743D6),
            surface: dark ? const Color(0xFF231E2C) : Colors.white,
            onSurface: dark ? const Color(0xFFF7F2FF) : const Color(0xFF201A2C),
            onSurfaceVariant: dark
                ? const Color(0xFFBDB3CB)
                : const Color(0xFF655D75),
            surfaceContainerLow: dark
                ? const Color(0xFF191620)
                : const Color(0xFFF8F7FB),
            surfaceContainerHighest: dark
                ? const Color(0xFF30283C)
                : const Color(0xFFF1EEF6),
            outlineVariant: dark
                ? const Color(0xFF463D52)
                : const Color(0xFFE7E2EE),
            secondaryContainer: dark
                ? const Color(0xFF392B56)
                : const Color(0xFFF1EBFF),
          );
      final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      );
      return ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surfaceContainerLow,
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          color: scheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: shape,
            minimumSize: const Size(48, 46),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: shape,
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'YTDL',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: AppShell(backend: backend),
    );
  }
}
