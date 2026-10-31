import 'package:flutter/material.dart';

import 'api.dart';
import 'home.dart';
import 'theme.dart';

void main() => runApp(MothballApp(api: MothballApi()));

class MothballApp extends StatelessWidget {
  const MothballApp({super.key, required this.api});

  final MothballApi api;

  /// The app theme, shared with tests and previews.
  static ThemeData theme(Brightness b) => buildTheme(b);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mothball',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: HomeScreen(api: api),
    );
  }
}
