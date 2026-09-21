import 'package:flutter_test/flutter_test.dart';
import 'package:showdup/services/billing.dart';

void main() {
  group('RevenueCat price copy', () {
    test('uses both live Play prices and a confirmed trial', () {
      expect(
        Billing.formatPriceLine(
          monthlyPrice: '₹79',
          annualPrice: '₹399',
          freeTrialDays: 7,
        ),
        '₹79 a month, or ₹399 a year with 7 days free.',
      );
    });

    test('does not invent a trial when Play reports none', () {
      expect(
        Billing.formatPriceLine(
          monthlyPrice: '₹79',
          annualPrice: '₹399',
        ),
        '₹79 a month, or ₹399 a year.',
      );
    });

    test('handles partial offerings', () {
      expect(
        Billing.formatPriceLine(monthlyPrice: '₹79'),
        '₹79 a month.',
      );
      expect(
        Billing.formatPriceLine(annualPrice: '₹399', freeTrialDays: 7),
        '₹399 a year with 7 days free.',
      );
    });

    test('returns null when no store plan is available', () {
      expect(Billing.formatPriceLine(), isNull);
    });

    test('ignores invalid trial lengths', () {
      expect(
        Billing.formatPriceLine(monthlyPrice: '₹79', freeTrialDays: 0),
        '₹79 a month.',
      );
    });
  });
}
