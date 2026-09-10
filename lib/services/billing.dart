import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../core/config.dart';
import '../core/constants.dart';

class Billing {
  static bool initialized = false;

  /// Links RevenueCat and OneSignal to the Firebase uid. Each provider is
  /// attempted even if the other fails; the first failure is rethrown.
  static Future<void> identify(String uid) async {
    Object? failure;
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

  static Future<void> paywall() async {
    if (!initialized) {
      throw StateError('Subscriptions are not configured for this build.');
    }
    final offerings = await Purchases.getOfferings();
    final offering = offerings.all[K.offeringDefault] ?? offerings.current;
    if (offering == null) {
      throw StateError('No subscription plans are available yet.');
    }
    await RevenueCatUI.presentPaywall(
      offering: offering,
      displayCloseButton: true,
    );
  }

  static Future<void> restore() async {
    if (!initialized) {
      throw StateError('Subscriptions are not configured for this build.');
    }
    await Purchases.restorePurchases();
  }

  /// RevenueCat throws when logging out an anonymous user, which happens if
  /// logIn failed earlier; that must not skip the OneSignal logout.
  static Future<void> logout() async {
    Object? failure;
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
