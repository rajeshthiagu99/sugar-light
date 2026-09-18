import 'package:flutter_test/flutter_test.dart';
import 'package:sugar_light/main.dart';
void main() {
  test('accepts only exact India rescue phases', () {
    expect(isExactRescueOffer(currency: 'INR', phases: [(priceMicros: 799000000, period: 'P1Y'), (priceMicros: 999000000, period: 'P1Y')]), isTrue);
    expect(isExactRescueOffer(currency: 'INR', phases: [(priceMicros: 799000000, period: 'P1Y')]), isFalse);
  });
  test('accepts only exact global rescue phases', () {
    expect(isExactRescueOffer(currency: 'USD', phases: [(priceMicros: 11990000, period: 'P1Y'), (priceMicros: 14990000, period: 'P1Y')]), isTrue);
    expect(isExactRescueOffer(currency: 'USD', phases: [(priceMicros: 10990000, period: 'P1Y'), (priceMicros: 14990000, period: 'P1Y')]), isFalse);
  });
}
