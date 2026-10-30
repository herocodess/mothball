import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/api.dart';
import 'package:mothball/logo.dart';
import 'package:mothball/main.dart';
import 'package:mothball/models.dart';

// Shaped exactly like the Go service's JSON, including Go's null for empty lists.
const statusJson = '''
{
  "freeBytes": 9663676416,
  "targetBytes": 53687091200,
  "waitingBytes": 0,
  "config": {"roots": null, "idleDays": 60, "autopilot": false, "targetFreeGB": 50, "autoEmptyDays": 0, "checkMinutes": 15},
  "lastScan": {
    "at": "2026-10-31T00:32:10.123456789+01:00",
    "projects": 2,
    "idle": [{"path": "/u/dev/app/node_modules", "project": "/u/dev/app", "pack": "javascript", "output": "node_modules",
              "bytes": 3000000, "lastWork": "2026-06-01T10:00:00+01:00", "idleDays": 151, "inGit": true, "dirty": false, "wake": "npm install"}],
    "idleBytes": 3000000,
    "active": null,
    "activeBytes": 0
  },
  "mothballed": null,
  "events": null
}
''';

void main() {
  test('parses the service status, nulls included', () {
    final st = Status.fromJson(jsonDecode(statusJson) as Map<String, dynamic>);
    expect(st.freeBytes, 9663676416);
    expect(st.config.roots, isEmpty);
    expect(st.lastScan!.idle.single.idleDays, 151);
    expect(st.lastScan!.at, isNotNull);
    expect(st.mothballed, isEmpty);
    expect(st.events, isEmpty);
  });

  test('config round-trips', () {
    final c = Status.fromJson(jsonDecode(statusJson) as Map<String, dynamic>).config.copyWith(autopilot: true);
    final back = MothballConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    expect(back.autopilot, isTrue);
    expect(back.targetFreeGB, 50);
  });

  test('formats bytes like the CLI', () {
    expect(humanBytes(512), '512 B');
    expect(humanBytes(3000000), '2.9 MB');
    expect(humanBytes(9663676416), '9.0 GB');
  });

  testWidgets('shows the offline screen when no service is running', (tester) async {
    await tester.pumpWidget(MothballApp(api: MothballApi(dir: '/nonexistent/mothball')));
    // The status check reads a file, which needs the real event loop.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.text('Start Mothball'), findsOneWidget);
    expect(find.byType(MothLogo), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
