import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production build contains no hidden reviewer bypass', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, isNot(contains('CLOSED_TEST_REVIEWER_ACCESS')));
    expect(source, isNot(contains('closedTestReviewerAccessEnabled')));
  });
}
