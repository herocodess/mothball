import 'package:flutter/material.dart';

import 'api.dart';
import 'home.dart';

void main() => runApp(MothballApp(api: MothballApi()));

const ink = Color(0xFF12161C);
const accent = Color(0xFF2BB673);
const ground = Color(0xFFF4F5F2);

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: b).copyWith(
    primary: dark ? accent : const Color(0xFF1E8A57),
    surface: dark ? const Color(0xFF15191F) : ground,
    onSurface: dark ? const Color(0xFFE9EBE7) : ink,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1C2128) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
  );
}

class MothballApp extends StatelessWidget {
  const MothballApp({super.key, required this.api});

  final MothballApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mothball',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomeScreen(api: api),
    );
  }
}
