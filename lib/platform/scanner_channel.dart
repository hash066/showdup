import 'package:flutter/services.dart';

/// Google's on-device code scanner. The camera UI belongs to Google Play
/// services, so ShowdUp never needs the camera permission. Native code hashes
/// the scanned value and only the SHA-256 hash crosses the channel.
class ScannerChannel {
  const ScannerChannel._();
  static const _channel = MethodChannel('app.showdup/scanner');

  /// Returns the code's hash, or null when the person closes the scanner.
  static Future<String?> scan() => _channel.invokeMethod<String>('scan');
}
