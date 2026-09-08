import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../core/config.dart';

class Billing {
  static bool initialized = false;
  static Future<void> identify(String uid) async {
    if (AppConfig.revenueCatKey.isNotEmpty) {
      if (!initialized) {
        await Purchases.configure(
          PurchasesConfiguration(AppConfig.revenueCatKey),
        );
        initialized = true;
      }
      await Purchases.logIn(uid);
    }
    if (AppConfig.oneSignalId.isNotEmpty) OneSignal.login(uid);
  }

  static Future<void> paywall() async {
    if (!initialized) {
      throw StateError('Subscriptions are not configured for this build.');
    }
    final offerings = await Purchases.getOfferings();
    final offering = offerings.all['default'];
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
}
