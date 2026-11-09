import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/api.dart';
import 'package:mothball/language.dart';
import 'package:mothball/main.dart';
import 'package:mothball/models.dart';
import 'package:mothball/settings.dart';

class _FakeApi extends MothballApi {
  _FakeApi() : super(dir: '/nonexistent');
  @override
  Future<Status> status() async => Status.fromJson(_sample);
  @override
  Future<ScanSummary> scan() async => Status.fromJson(_sample).lastScan!;
}

final _sample = <String, dynamic>{
  'access': {'fullDisk': true},
  'freeBytes': 71 * 1073741824,
  'targetBytes': 50 * 1073741824,
  'waitingBytes': 3 * 1073741824,
  'config': {'idleDays': 60, 'autopilot': true, 'targetFreeGB': 50, 'autoEmptyDays': 7, 'checkMinutes': 15, 'onboarded': true},
  'lastScan': {
    'at': '2026-11-09T10:00:00Z',
    'projects': 312,
    'idle': [
      for (final (i, n) in ['sque-frontend › apps/v2', 'cordros_cape', 'pact-mobile-v2'].indexed)
        {
          'path': '/Users/hero/dev/p$i/node_modules',
          'project': '/Users/hero/dev/p$i',
          'name': n,
          'pack': 'javascript',
          'bytes': (i + 1) * 2147483648,
          'idleDays': 1 + i * 100,
        },
    ],
    'idleBytes': 6 * 2147483648,
    'caches': [
      {'id': 'npm', 'name': 'npm cache', 'policy': 'auto', 'bytes': 2684354560, 'how': 'Runs npm cache clean --force.'},
      {'id': 'gradle', 'name': 'Gradle caches', 'policy': 'ask', 'bytes': 0, 'how': 'Moves Gradle caches to the Trash.'},
      {'id': 'chrome', 'name': 'Chrome cache', 'policy': 'auto', 'bytes': 1073741824, 'how': '', 'blocked': 'Chrome is open'},
    ],
    'cacheBytes': 3758096384,
  },
  'mothballed': [
    {'path': '/Users/hero/dev/eventbrdge', 'name': 'eventbrdge', 'bytes': 1610612736, 'returned': true, 'commands': ['npm install']},
    {'path': '/Users/hero/dev/kuvori', 'name': 'kuvori', 'bytes': 805306368, 'returned': false, 'commands': []},
  ],
  'events': [
    {'at': '2026-11-09T09:00:00Z', 'kind': 'autopilot', 'message': 'Put away 2 folders.', 'bytes': 2147483648},
    {'at': '2026-11-08T09:00:00Z', 'kind': 'emptied', 'message': 'Emptied 1 folder.', 'bytes': 0},
  ],
};

void main() {
  const locales = AppLocalizations.supportedLocales;

  test('every language in the Settings list has translations', () {
    final codes = locales.map((l) => l.languageCode).toSet();
    for (final (code, _) in languages) {
      expect(codes, contains(code));
    }
    expect(codes.length, languages.length);
  });

  for (final locale in locales) {
    group('${locale.languageCode}:', () {
      Future<void> pumpApp(WidgetTester tester) async {
        tester.view.physicalSize = const Size(1100, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MothballApp(api: _FakeApi(), locale: locale));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
      }

      testWidgets('home screen lays out', (tester) async {
        await pumpApp(tester);
        final context = tester.element(find.byType(Scaffold).first);
        final t = AppLocalizations.of(context);
        expect(t.localeName, startsWith(locale.languageCode));
        expect(find.text(t.idleProjects), findsOneWidget);
        expect(find.text(t.mothballed), findsOneWidget);
        expect(Directionality.of(context), locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr);
        expect(tester.takeException(), isNull);
      });

      testWidgets('settings lay out', (tester) async {
        await pumpApp(tester);
        await tester.tap(find.byIcon(Icons.tune_rounded));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(find.byType(SettingsScreen), findsOneWidget);
        final t = AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
        expect(find.text(t.language), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('sizes use the language\'s decimal mark and units', (tester) async {
    final out = <String, String>{};
    for (final code in ['en', 'fr', 'ar']) {
      await tester.pumpWidget(MaterialApp(
        locale: Locale(code),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) {
          out[code] = sizeOf(context, 20723217203); // 19.3 GB
          return const SizedBox();
        }),
      ));
    }
    expect(out['en'], '19.3\u00A0GB');
    expect(out['fr'], '19,3\u00A0Go');
    // Arabic keeps Western digits and holds the size together left to right.
    expect(out['ar'], '\u206619.3\u00A0GB\u2069');
  });

  test('sentences take their parts in the order they appear in English', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.idleSummary('60', '19.3 GB', '6 folders'), 'Untouched for 60+ days · 19.3 GB of build output in 6 folders');
    expect(en.legendWaiting('2.0 GB', 'in the Trash'), '2.0 GB waiting in the Trash');
    expect(en.cleanedWithError('1.0 GB', 'Chrome cache', 'Chrome is open'), 'Cleaned 1.0 GB. Chrome cache: Chrome is open');
    expect(en.putAwayResult(2, '3.0 GB'), 'Put away 3.0 GB, left 2 alone.');
    final ja = await AppLocalizations.delegate.load(const Locale('ja'));
    expect(ja.idleSummary('60', '19.3 GB', '6 個のフォルダ'), '60 日以上未使用 · 6 個のフォルダに 19.3 GB のビルド成果物');
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(ar.projectsCount(2), 'مشروعان');
    expect(ar.projectsCount(5), '5 مشاريع');
    expect(ar.projectsCount(312), '312 مشروعًا'); // ends in 11 to 99: the "many" form
    expect(ar.projectsCount(100), '100 مشروع');
  });

  test('the language setting round-trips through the config', () {
    final c = MothballConfig.fromJson({'language': 'ar'});
    expect(c.language, 'ar');
    expect(c.copyWith(theme: 'dark').language, 'ar');
    expect(c.copyWith(language: '').toJson()['language'], '');
    expect(localeOf(''), isNull);
    expect(localeOf('fr'), const Locale('fr'));
    expect(localeOf('xx'), isNull);
  });
}
