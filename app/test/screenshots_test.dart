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

  const sup = '/System/Library/Fonts/Supplemental';
  await load('Roboto', ['$sup/Arial.ttf', '$sup/Arial Bold.ttf']);
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  await load('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

Future<void> shoot(WidgetTester tester, Widget app, String name, {Size size = const Size(1100, 860)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 500));
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('screenshots/$name.png'));
}

void main() {
  setUpAll(loadFonts);

  testWidgets('onboarding', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: false, onboarded: false))), '1-onboarding'));
  testWidgets('home, access missing', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: false, onboarded: true))), '2-home-reminder', size: const Size(1100, 1400)));
  testWidgets('home', (t) => shoot(t, MothballApp(api: FakeApi(sample(fullDisk: true, onboarded: true))), '3-home', size: const Size(1100, 1320)));
  testWidgets('settings', (t) {
    final c = Status.fromJson(sample(fullDisk: true, onboarded: true)).config;
    return shoot(
      t,
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MothballApp.theme(Brightness.light),
        home: SettingsScreen(config: c, onSave: (_) async {}),
      ),
      '4-settings',
    );
  });
  testWidgets('not running', (t) => shoot(t, MothballApp(api: MothballApi(dir: '/nonexistent')), '5-not-running', size: const Size(1100, 700)));
}
