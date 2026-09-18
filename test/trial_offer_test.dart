import 'package:flutter_test/flutter_test.dart';
import 'package:sugar_light/main.dart';

void main() {
  test('rejects monthly base plan without 3-day free trial', () {
    expect(
      hasRequiredTrial([(priceMicros: 199000000, period: 'P1M')]),
      isFalse,
    );
  });
  test('accepts only an exact 3-day zero-price phase', () {
    expect(
      hasRequiredTrial([
        (priceMicros: 0, period: 'P3D'),
        (priceMicros: 199000000, period: 'P1M'),
      ]),
      isTrue,
    );
  });
}
