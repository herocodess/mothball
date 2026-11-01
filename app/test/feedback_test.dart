import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/feedback.dart';

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

  test('stack link opens the stack template', () {
    expect(Uri.parse(FeedbackLinks.newStack('')).queryParameters['template'], 'new_stack.yml');
  });

  test('an unknown version is left out rather than sent empty', () {
    expect(Uri.parse(FeedbackLinks.bugReport('')).queryParameters.containsKey('version'), isFalse);
  });
}
