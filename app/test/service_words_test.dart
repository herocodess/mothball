import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/language.dart';
import 'package:mothball/models.dart';
import 'package:mothball/service_words.dart';

/// Builds a widget in [locale] and hands its context to [body].
Future<void> inLocale(WidgetTester tester, Locale locale, void Function(BuildContext) body) async {
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Builder(builder: (context) {
      body(context);
      return const SizedBox();
    }),
  ));
}

CacheInfo cache(String id, {String blocked = '', String by = '', String tool = ''}) =>
    CacheInfo(id: id, name: 'service name', policy: 'auto', bytes: 1, how: 'service how', blocked: blocked, blockedBy: by, missingTool: tool);

void main() {
  // Every cache the service knows, read from its source.
  final ids = RegExp(r'\bid:\s*"([a-z0-9-]+)"')
      .allMatches(File('../core/caches/caches.go').readAsStringSync())
      .map((m) => m.group(1)!)
      .toList();
  // Every event code the service sends.
  final codes = RegExp(r'Code\w+\s*=\s*"(\w+)"')
      .allMatches(File('../core/service/service.go').readAsStringSync())
      .map((m) => m.group(1)!)
      .toList();

  test('the service sources were found', () {
    expect(ids.length, greaterThan(20));
    expect(codes, contains('cleanedCaches'));
  });

  testWidgets('every cache has a translated name and description in every language', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await inLocale(tester, locale, (context) {
        for (final id in ids) {
          expect(cacheName(context, id, 'service name'), isNot('service name'), reason: '$id name in ${locale.languageCode}');
          expect(cacheHow(context, cache(id)), isNot('service how'), reason: '$id description in ${locale.languageCode}');
        }
      });
    }
  });

  testWidgets('every event code is translated in every language', (tester) async {
    for (final locale in AppLocalizations.supportedLocales) {
      await inLocale(tester, locale, (context) {
        for (final code in codes) {
          final e = ServiceEvent(at: null, kind: 'autopilot', message: 'service message', bytes: 0, code: code, arg: '0.1.7');
          expect(eventDetail(context, e), isNot('service message'), reason: '$code in ${locale.languageCode}');
        }
      });
    }
  });

  testWidgets('unknown caches and errors keep the service text', (tester) async {
    await inLocale(tester, const Locale('fr'), (context) {
      expect(cacheName(context, 'something-new', 'Something new'), 'Something new');
      expect(cacheHow(context, cache('something-new')), 'service how');
      final err = ServiceEvent(at: null, kind: 'error', message: 'scan failed: disk gone', bytes: 0);
      expect(eventDetail(context, err), 'scan failed: disk gone');
    });
  });

  testWidgets('waiting reasons name the app or tool', (tester) async {
    await inLocale(tester, const Locale('en'), (context) {
      expect(cacheWaiting(context, cache('chrome', blocked: 'Google Chrome is running', by: 'Google Chrome')), 'Waiting: Google Chrome is open');
      expect(cacheWaiting(context, cache('npm', blocked: 'npm is not installed', tool: 'npm')), 'Waiting: npm is not installed');
      // An older service only sends the English reason.
      expect(cacheWaiting(context, cache('npm', blocked: 'npm is not installed')), 'Waiting: npm is not installed');
      expect(cacheWaiting(context, cache('npm')), '');
    });
  });
}
