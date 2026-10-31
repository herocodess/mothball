// Renders the main screens to PNG files with sample data, for previews and
// README screenshots. Skipped in normal test runs; generate with:
//
//   flutter test --update-goldens --tags screenshots test/screenshots_test.dart
//
// Images land in test/screenshots/. Fonts are loaded from the system so text
// renders as real text; run it on macOS.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/api.dart';
import 'package:mothball/main.dart';
import 'package:mothball/models.dart';
import 'package:mothball/settings.dart';
import 'package:mothball/theme.dart';

class FakeApi extends MothballApi {
  FakeApi(this.json) : super(dir: '/nonexistent');
  final Map<String, dynamic> json;
  @override
  Future<Status> status() async => Status.fromJson(json);
  @override
  Future<ScanSummary> scan() async => Status.fromJson(json).lastScan!;
  @override
  Future<MothballConfig> saveConfig(MothballConfig c) async => c;
}

Map<String, dynamic> sample({required bool fullDisk, required bool onboarded}) {
  Map<String, dynamic> cand(String project, String out, String pack, int gb10, int idle) => {
        'path': '/Users/hero/dev/$project/$out',
        'project': '/Users/hero/dev/$project',
        'pack': pack,
        'bytes': gb10 * 107374182,
        'idleDays': idle,
        'dirty': false,
        'wake': '',
      };
  final idle = [
    cand('sque-frontend/apps/v2', '.next', 'javascript', 57, 150),
    cand('sque-frontend/apps/v1', 'node_modules', 'javascript', 55, 150),
    cand('cordros_cape', 'build', 'flutter', 29, 149),
    cand('nrs_workspace', '.dart_tool', 'flutter', 22, 111),
    cand('pact-mobile-v2', 'ios/Pods', 'cocoapods', 18, 1029),
    cand('serendipity_mobile', 'build', 'gradle', 12, 346),
  ];
  return {
    'access': {
      'fullDisk': fullDisk,
      'skipped': fullDisk ? [] : ['/Users/hero/Desktop', '/Users/hero/Documents', '/Users/hero/Downloads'],
      'executable': '/Applications/Mothball.app/Contents/MacOS/mothball',
    },
    'freeBytes': 71 * 1073741824,
    'targetBytes': 50 * 1073741824,
    'waitingBytes': 0,
    'config': {
      'roots': null,
      'idleDays': 60,
      'autopilot': true,
      'targetFreeGB': 50,
      'autoEmptyDays': 7,
      'checkMinutes': 15,
      'onboarded': onboarded,
    },
    'lastScan': {
      'at': '2026-10-31T13:20:00+01:00',
      'projects': 312,
      'idle': idle,
      'idleBytes': idle.fold<int>(0, (s, c) => s + (c['bytes'] as int)),
      'caches': [
        {'id': 'xcode-derived-data', 'name': 'Xcode DerivedData', 'policy': 'auto', 'bytes': 7516192768, 'how': 'Moves Xcode build data to the Trash. Xcode rebuilds it on the next build.'},
        {'id': 'gradle', 'name': 'Gradle caches', 'policy': 'ask', 'bytes': 10630044058, 'how': 'Moves Gradle caches to the Trash while no Gradle daemon is running.'},
        {'id': 'cocoapods', 'name': 'CocoaPods cache', 'policy': 'auto', 'bytes': 5476083302, 'how': 'Runs pod cache clean --all.'},
        {'id': 'npm', 'name': 'npm cache', 'policy': 'auto', 'bytes': 2684354560, 'how': 'Runs npm cache clean --force.'},
        {'id': 'vscode', 'name': 'VS Code caches', 'policy': 'auto', 'bytes': 912680550, 'how': 'Moves web caches to the Trash while VS Code is closed.', 'blocked': 'Code is running'},
        {'id': 'android-emulators', 'name': 'Android emulators', 'policy': 'report', 'bytes': 12133306368, 'how': 'Delete emulators you no longer use in Android Studio.'},
      ],
      'cacheBytes': 26306674688,
    },
    'mothballed': [
      {'path': '/Users/hero/dev/kuvori-mobile', 'since': '2026-10-02T10:00:00Z', 'bytes': 860000000, 'returned': true, 'commands': ['flutter pub get']},
      {'path': '/Users/hero/dev/driftlog', 'since': '2026-09-20T10:00:00Z', 'bytes': 1240000000, 'returned': false, 'commands': ['pnpm install']},
    ],
    'events': [
      {'at': '2026-10-30T09:00:00Z', 'kind': 'autopilot', 'message': 'Put away build output from idle projects; it is emptied from the Trash after the grace period', 'bytes': 9126805504},
      {'at': '2026-10-31T09:00:00Z', 'kind': 'emptied', 'message': 'Emptied folders Mothball put in the Trash', 'bytes': 4294967296},
    ],
  };
}

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File(f);
      if (file.existsSync()) loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  const fonts = 'assets/fonts';
  await load('Instrument Sans', [
    for (final w in ['Regular', 'Italic', 'Medium', 'SemiBold']) '$fonts/InstrumentSans-$w.ttf',
  ]);
  await load('Menlo', ['/System/Library/Fonts/Menlo.ttc']);

  // The Flutter SDK folder: FLUTTER_ROOT when set, else found from the test runner's path.
  var sdk = Platform.environment['FLUTTER_ROOT'] ?? '';
  if (sdk.isEmpty) {
    final exe = Platform.resolvedExecutable;
    final i = exe.indexOf('/bin/cache/');
    sdk = i > 0 ? exe.substring(0, i) : '';
  }
  await load('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

Future<void> shoot(WidgetTester tester, Widget app, String name,
    {Size size = const Size(1100, 860), Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  // Tests draw shadows as solid blocks by default; draw them as the app does.
  debugDisableShadows = false;
  await tester.pumpWidget(app);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  // Let the staggered entrances, count-ups and bars finish.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('screenshots/$name.png'));
  await tester.pumpWidget(const SizedBox());
  debugDisableShadows = true;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('onboarding', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: false, onboarded: false))), '1-onboarding'));
  testWidgets('home, access missing', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: false, onboarded: true))), '2-home-reminder', size: const Size(1100, 2300)));
  testWidgets('home', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: true, onboarded: true))), '3-home', size: const Size(1100, 2240)));
  testWidgets('home, dark', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: true, onboarded: true))), '6-home-dark',
      size: const Size(1100, 2240), brightness: Brightness.dark));
  testWidgets('settings', (t) {
    final c = Status.fromJson(sample(fullDisk: true, onboarded: true)).config;
    return shoot(
      t,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: SettingsScreen(config: c, onSave: (_) async {}),
      ),
      '4-settings',
      size: const Size(1100, 1060),
    );
  });
  testWidgets('not running', (t) => shoot(t, MothballApp(api: MothballApi(dir: '/nonexistent')), '5-not-running', size: const Size(1100, 760)));
}
