import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/feedback.dart';
import 'package:mothball/language.dart';

void main() {
  test('bug report link opens the bug template with version and system filled in', () {
    final u = Uri.parse(FeedbackLinks.bugReport('0.1.4'));
    expect(u.host, 'github.com');
    expect(u.path, '/herocodess/mothball/issues/new');
    expect(u.queryParameters['template'], 'bug_report.yml');
    expect(u.queryParameters['version'], '0.1.4');
    expect(u.queryParameters['os'], isNotEmpty);
    expect(u.queryParameters['chip'], isNotEmpty);
  });

  test('translation link picks the language in the form, for every translation', () {
    // GitHub only preselects a dropdown when the value matches an option exactly.
    final form = File('../.github/ISSUE_TEMPLATE/translation.yml').readAsStringSync();
    for (final (code, _) in languages) {
      if (code == 'en') continue;
      final name = FeedbackLinks.translationLanguage(code);
      expect(form, contains('        - $name\n'), reason: '$code is missing from the form');
      final u = Uri.parse(FeedbackLinks.translation('0.1.7', name));
      expect(u.queryParameters['template'], 'translation.yml');
      expect(u.queryParameters['language'], name);
      expect(u.queryParameters['version'], '0.1.7');
    }
  });

  test('stack link opens the stack template', () {
    expect(Uri.parse(FeedbackLinks.newStack('')).queryParameters['template'], 'new_stack.yml');
  });

  test('an unknown version is left out rather than sent empty', () {
    expect(Uri.parse(FeedbackLinks.bugReport('')).queryParameters.containsKey('version'), isFalse);
  });
}
