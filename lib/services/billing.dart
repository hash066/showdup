import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../core/config.dart';
import '../core/constants.dart';

class Billing {
  static bool initialized = false;
  static String? _uid;

  /// Links RevenueCat and OneSignal to the Firebase uid. Each provider is
  /// attempted even if the other fails; the first failure is rethrown.
  static Future<void> identify(String uid) async {
    Object? failure;
    _uid = uid;
    if (AppConfig.revenueCatKey.isNotEmpty) {
      try {
        if (!initialized) {
          await Purchases.configure(
            PurchasesConfiguration(AppConfig.revenueCatKey),
          );
          initialized = true;
        }
        await Purchases.logIn(uid);
      } catch (e) {
        failure = e;
      }
    }
    if (AppConfig.oneSignalId.isNotEmpty) {
      try {
        await OneSignal.login(uid);
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure != null) throw failure;
  }

  /// A purchase made while RevenueCat is anonymous lands on a $RCAnonymousID
  /// the webhook cannot map to a Firebase user, so Pro would never unlock.
  /// Re-link (logIn may have failed at launch) or refuse to sell.
  static Future<void> _ensureLinked() async {
    if (!initialized) {
      throw StateError('Subscriptions are not configured for this build.');
    }
    if (!await Purchases.isAnonymous) return;
    final uid = _uid;
    if (uid != null) {
      try {
        await Purchases.logIn(uid);
      } catch (_) {}
    }
    if (await Purchases.isAnonymous) {
      throw StateError(
        'We couldn’t link purchases to your account. Check your connection and try again.',
      );
    }
  }

  /// Returns a message to show, or null when the user simply closed the paywall.
  static Future<String?> paywall() async {
    await _ensureLinked();
    final offerings = await Purchases.getOfferings();
    final offering = offerings.all[K.offeringDefault];
    if (offering == null) {
      throw StateError('No subscription plans are available yet.');
    }
    final result = await RevenueCatUI.presentPaywall(
      offering: offering,
      displayCloseButton: true,
    );
    return switch (result) {
      PaywallResult.purchased || PaywallResult.restored =>
        'Purchase received. Pro unlocks as soon as the server confirms it.',
      PaywallResult.error => throw StateError(
        'The purchase didn’t complete. Please try again.',
      ),
      _ => null,
    };
  }

  static Future<String?> restore() async {
    await _ensureLinked();
    await Purchases.restorePurchases();
    return 'Purchase information refreshed. Entitlements update after server confirmation.';
  }

  /// RevenueCat throws when logging out an anonymous user, which happens if
  /// logIn failed earlier; that must not skip the OneSignal logout.
  static Future<void> logout() async {
    Object? failure;
    _uid = null;
    if (initialized) {
      try {
        if (!await Purchases.isAnonymous) await Purchases.logOut();
      } catch (e) {
        failure = e;
      }
    }
    if (AppConfig.oneSignalId.isNotEmpty) {
      try {
        await OneSignal.logout();
      } catch (e) {
        failure ??= e;
      }
    }
    if (failure != null) throw failure;
  }
}
