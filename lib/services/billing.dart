import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config.dart';
import '../core/constants.dart';

enum BillingResult { purchased, restored, cancelled }

/// RevenueCat setup for a device-local first release.
///
/// This deliberately does not call [Purchases.logIn]. The locally persisted
/// RevenueCat app user ID remains stable across launches, while Firebase (if
/// enabled for backup) stays completely separate from billing identity.
class Billing {
  static const _appUserIdPreference = 'revenuecat_app_user_id';
  static bool initialized = false;
  static Future<void>? _initializing;
  static String? _appUserId;
  static final ValueNotifier<bool> pro = ValueNotifier(false);
  static final ValueNotifier<int?> proExpiresAtEpochMs = ValueNotifier(null);
  static final ValueNotifier<int> entitlementRevision = ValueNotifier(0);
  static Timer? _expiryTimer;

  static bool get isPro => pro.value;
  static String? get appUserId => _appUserId;

  static Future<void> initialize(SharedPreferences prefs) {
    if (initialized || AppConfig.revenueCatKey.isEmpty) {
      return Future.value();
    }
    return _initializing ??= _initialize(prefs);
  }

  static Future<void> _initialize(SharedPreferences prefs) async {
    try {
      if (kReleaseMode && AppConfig.revenueCatKey.startsWith('test_')) {
        throw StateError(
          'RevenueCat Test Store keys are forbidden in release builds.',
        );
      }
      final existingId = prefs.getString(_appUserIdPreference);
      final id = existingId ?? _newAppUserId();
      if (existingId == null) {
        await prefs.setString(_appUserIdPreference, id);
      }

      await Purchases.configure(
        PurchasesConfiguration(AppConfig.revenueCatKey)..appUserID = id,
      );
      _appUserId = id;
      initialized = true;
      Purchases.addCustomerInfoUpdateListener(_updateEntitlement);
      await refresh();
    } finally {
      _initializing = null;
    }
  }

  static Future<void> refresh() async {
    if (!initialized) return;
    _updateEntitlement(await Purchases.getCustomerInfo());
  }

  static Future<BillingResult> paywall() async {
    _requireInitialized();
    final offerings = await Purchases.getOfferings();
    final offering = offerings.current ?? offerings.all['default'];
    if (offering == null) {
      throw StateError('No subscription plans are available yet.');
    }
    final result = await RevenueCatUI.presentPaywall(
      offering: offering,
      displayCloseButton: true,
    );
    if (result == PaywallResult.error) {
      throw StateError(
        'Google Play could not complete the purchase. Try again.',
      );
    }
    await refresh();
    return switch (result) {
      PaywallResult.purchased => BillingResult.purchased,
      PaywallResult.restored => BillingResult.restored,
      PaywallResult.cancelled ||
      PaywallResult.notPresented => BillingResult.cancelled,
      PaywallResult.error => throw StateError('Unexpected purchase error.'),
    };
  }

  /// The live price line for the Pro page, built from the store products in
  /// the current offering, like "₹80 a month, or ₹400 a year." Null when
  /// billing is off or the offering is not set up, so the
  /// page falls back to its own copy.
  static Future<String?> priceLine() async {
    if (!initialized) return null;
    try {
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current ?? offerings.all['default'];
      final monthly = offering?.monthly?.storeProduct;
      final annual = offering?.annual?.storeProduct;
      final trial = _freeTrialDays(annual) ?? _freeTrialDays(monthly);
      return formatPriceLine(
        monthlyPrice: monthly?.priceString,
        annualPrice: annual?.priceString,
        freeTrialDays: trial,
      );
    } catch (_) {
      return null;
    }
  }

  /// Formats store-provided prices without inventing a plan or trial.
  ///
  /// Keeping this pure makes the failure and partial-offering cases testable
  /// without initializing the native Google Play Billing client.
  @visibleForTesting
  static String? formatPriceLine({
    String? monthlyPrice,
    String? annualPrice,
    int? freeTrialDays,
  }) {
    if (monthlyPrice == null && annualPrice == null) return null;
    final trialText = freeTrialDays != null && freeTrialDays > 0
        ? ' with $freeTrialDays days free'
        : '';
    if (monthlyPrice != null && annualPrice != null) {
      return '$monthlyPrice a month, or $annualPrice a year$trialText.';
    }
    if (monthlyPrice != null) return '$monthlyPrice a month$trialText.';
    return '$annualPrice a year$trialText.';
  }

  static int? _freeTrialDays(StoreProduct? product) {
    final intro = product?.introductoryPrice;
    if (intro == null || intro.price != 0) return null;
    final days = switch (intro.periodUnit) {
      PeriodUnit.day => intro.periodNumberOfUnits,
      PeriodUnit.week => intro.periodNumberOfUnits * 7,
      PeriodUnit.month => intro.periodNumberOfUnits * 30,
      PeriodUnit.year => intro.periodNumberOfUnits * 365,
      PeriodUnit.unknown => null,
    };
    return days != null && days > 0 ? days : null;
  }

  static Future<BillingResult> restore() async {
    _requireInitialized();
    _updateEntitlement(await Purchases.restorePurchases());
    return BillingResult.restored;
  }

  static void _updateEntitlement(CustomerInfo info) {
    _expiryTimer?.cancel();
    final entitlement = info.entitlements.active[K.entitlementPro];
    final expiry = entitlement?.expirationDate == null
        ? null
        : DateTime.tryParse(entitlement!.expirationDate!)?.toUtc();
    // ShowdUp sells Pro only as a subscription. A missing/unparseable expiry
    // must therefore fail closed instead of leaving app restrictions enabled
    // forever from stale cached entitlement state.
    final verifiedActive =
        entitlement?.isActive == true &&
        expiry != null &&
        expiry.isAfter(DateTime.now().toUtc());
    proExpiresAtEpochMs.value = expiry?.millisecondsSinceEpoch;
    pro.value = verifiedActive;
    entitlementRevision.value++;
    if (verifiedActive) {
      _expiryTimer = Timer(expiry.difference(DateTime.now().toUtc()), () {
        pro.value = false;
        entitlementRevision.value++;
      });
    }
  }

  static void _requireInitialized() {
    if (!initialized) {
      throw StateError('Subscriptions are not configured for this build.');
    }
  }

  static String _newAppUserId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return 'showdup_${bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
