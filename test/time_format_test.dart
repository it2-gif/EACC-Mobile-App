import 'package:chatt_eacc/utils/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('12-hour time formatting', () {
    test('formats midnight with AM', () {
      expect(formatClockTime(DateTime(2026, 6, 18, 0, 5)), '12:05 AM');
    });

    test('formats morning with AM', () {
      expect(formatClockTime(DateTime(2026, 6, 18, 9, 7)), '9:07 AM');
    });

    test('formats noon with PM', () {
      expect(formatClockTime(DateTime(2026, 6, 18, 12, 0)), '12:00 PM');
    });

    test('formats afternoon with PM', () {
      expect(formatClockTime(DateTime(2026, 6, 18, 13, 30)), '1:30 PM');
    });
  });
}
