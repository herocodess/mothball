import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

/// The language the user picked, as saved in the config: '' follows the
/// system, otherwise a code from [languages].
final language = ValueNotifier<String>('');

/// The languages Mothball speaks, each named in itself so people can find
/// their own in the list.
const languages = <(String, String)>[
  ('en', 'English'),
  ('ar', 'العربية'),
  ('es', 'Español'),
  ('fr', 'Français'),
  ('ja', '日本語'),
  ('pt', 'Português (Brasil)'),
  ('zh', '简体中文'),
];

/// The locale for a saved language code, or null to follow the system.
Locale? localeOf(String code) {
  if (code.isEmpty) return null;
  for (final (c, _) in languages) {
    if (c == code) return Locale(c);
  }
  return null;
}

extension Words on BuildContext {
  /// This screen's text in the current language.
  AppLocalizations get t => AppLocalizations.of(this);

  /// Whether the current language is written right to left.
  bool get rtl => Directionality.of(this) == TextDirection.rtl;
}

/// Languages written in Latin letters can take Mothball's tight headline
/// spacing and all-caps labels. Arabic letters must join, and Chinese and
/// Japanese have no capitals, so they keep normal spacing.
bool latinScript(BuildContext context) =>
    const {'en', 'es', 'fr', 'pt'}.contains(Localizations.maybeLocaleOf(context)?.languageCode ?? 'en');

// Keeps numbers, sizes and paths reading left to right inside right-to-left
// text: "19.3 GB" stays one unit instead of being reordered.
const _lri = '\u2066';
const _pdi = '\u2069';

/// Wraps text that must read left to right (a size, a path, a command) so
/// it stays whole inside a right-to-left sentence.
String ltr(BuildContext context, String s) => context.rtl ? '$_lri$s$_pdi' : s;

/// A size in the current language: 1024-based, one decimal, like the CLI,
/// with the local decimal mark and unit names ("19,3 Go" in French).
String sizeOf(BuildContext context, int b) {
  final t = context.t;
  final units = [t.unitKB, t.unitMB, t.unitGB, t.unitTB, 'PB', 'EB'];
  String s;
  if (b < 1024) {
    s = '$b ${t.unitB}';
  } else {
    var value = b / 1024;
    var i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    s = '${decimal(context, value)} ${units[i]}';
  }
  return ltr(context, s);
}

/// A whole number of gigabytes, like the autopilot target.
String gigabytes(BuildContext context, int gb) => ltr(context, '${NumberFormat.decimalPattern(_numbers(context)).format(gb)} ${context.t.unitGB}');

// Arabic text keeps Western digits (0-9), the same digits the counts and
// paths around them use, so a size never mixes two kinds of numerals.
String _numbers(BuildContext context) => context.t.localeName == 'ar' ? 'en' : context.t.localeName;

/// One decimal place with the local decimal mark.
String decimal(BuildContext context, double v, {int digits = 1}) {
  final f = NumberFormat.decimalPatternDigits(locale: _numbers(context), decimalDigits: digits);
  return f.format(v);
}

/// "45%" or "45 %", as the language writes it.
String percent(BuildContext context, double fraction) => context.t.percent((fraction * 100).round().toString());

/// A calendar date, like "4 November 2026" or "2026年11月4日".
String longDate(BuildContext context, DateTime d) => DateFormat.yMMMMd(context.t.localeName).format(d);

/// How long ago something happened, briefly.
String ago(BuildContext context, DateTime at) {
  final t = context.t;
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return t.justNow;
  if (d.inHours < 1) return t.minutesAgo('${d.inMinutes}');
  if (d.inDays < 1) return t.hoursAgo('${d.inHours}');
  if (d.inDays < 30) return t.daysAgo('${d.inDays}');
  return DateFormat.yMd(t.localeName).format(at);
}

/// "to the Trash" or "to the Recycle Bin", in the current language.
String toTrash(BuildContext context) => Platform.isWindows ? context.t.toRecycleBin : context.t.toTrash;

/// "in the Trash" or "in the Recycle Bin", in the current language.
String inTrash(BuildContext context) => Platform.isWindows ? context.t.inRecycleBin : context.t.inTrash;

/// "Show in Finder", "Show in File Explorer" or "Show in Files".
String showInFileManager(BuildContext context) {
  if (Platform.isMacOS) return context.t.showInFinder;
  if (Platform.isWindows) return context.t.showInFileExplorer;
  return context.t.showInFiles;
}

/// The names of up to three folders, as Finder shows them in this language:
/// "Desktop, Documents and Downloads".
String folderList(BuildContext context, List<String> paths) {
  final t = context.t;
  String local(String name) => switch (name) {
        'Desktop' => t.folderDesktop,
        'Documents' => t.folderDocuments,
        'Downloads' => t.folderDownloads,
        _ => name,
      };
  final names = paths.take(3).map((p) => local(p.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last)).toList();
  return switch (names.length) {
    0 => t.listOfThree(t.folderDesktop, t.folderDocuments, t.folderDownloads),
    1 => names.single,
    2 => t.listOfTwo(names[0], names[1]),
    _ => t.listOfThree(names[0], names[1], names[2]),
  };
}

/// How many folders [folderList] names, for agreement ("is" or "are").
int folderCount(List<String> paths) => paths.isEmpty ? 3 : paths.length.clamp(1, 3);
