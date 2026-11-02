import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/places.dart';

void main() {
  test('home folder becomes ~ and short paths stay whole', () {
    expect(Places.display('/Users/hero/dev/InviteNaija/apps/web', home: '/Users/hero'), '~/dev/InviteNaija/apps/web');
  });

  test('long paths keep the start and the last three folders', () {
    expect(Places.display('/Users/hero/dev/clients/kraftyn/InviteNaija/apps/web', home: '/Users/hero'), '~/…/InviteNaija/apps/web');
    expect(Places.display('/opt/work/a/b/c/d/e', home: '/Users/hero'), '/…/c/d/e');
  });

  test('Windows paths', () {
    expect(Places.display(r'C:\Users\hero\source\repos\shop\apps\web', home: r'C:\Users\hero'), r'~\…\shop\apps\web');
  });

  test('a folder that only shares a prefix with home is left alone', () {
    expect(Places.display('/Users/heroine/x', home: '/Users/hero'), '/Users/heroine/x');
  });
}
