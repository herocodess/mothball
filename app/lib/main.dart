import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'home.dart';
import 'language.dart';
import 'theme.dart';

void main() => runApp(MothballApp(api: MothballApi()));

class MothballApp extends StatelessWidget {
  const MothballApp({super.key, required this.api, this.locale});

  final MothballApi api;

  /// A fixed language, for tests and screenshots. Otherwise the saved
  /// choice, or the system's.
  final Locale? locale;

  /// The app theme, shared with tests and previews.
  static ThemeData theme(Brightness b) => buildTheme(b);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appearance, language]),
      builder: (context, _) => MaterialApp(
        title: 'Mothball',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: appearance.value,
        themeAnimationDuration: const Duration(milliseconds: 350),
        locale: locale ?? localeOf(language.value),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Headline letter spacing suits Latin letters only; see latinScript.
        builder: (context, child) => latinScript(context) ? child! : Theme(data: forScript(Theme.of(context)), child: child!),
        home: HomeScreen(api: api),
      ),
    );
  }
}
