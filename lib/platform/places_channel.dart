import 'package:flutter/services.dart';

class PickedPlace {
  const PickedPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;

  factory PickedPlace.fromMap(Map<dynamic, dynamic> map) => PickedPlace(
    id: map['id'] as String? ?? '',
    name: map['name'] as String? ?? 'Selected gym',
    address: map['address'] as String? ?? '',
    lat: (map['lat'] as num).toDouble(),
    lng: (map['lng'] as num).toDouble(),
  );
}

class PlacesChannel {
  static const _channel = MethodChannel('app.showdup/places');

  static Future<PickedPlace?> pickPlace({String initialQuery = ''}) async {
    final result = await _channel.invokeMethod<Map>('pickPlace', {
      'initialQuery': initialQuery,
    });
    return result == null ? null : PickedPlace.fromMap(result);
  }

  /// Whether this build carries a Google Places key. Without one, place
  /// search falls back to [search].
  static Future<bool> configured() async {
    try {
      return await _channel.invokeMethod<bool>('configured') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Free place lookup through Android's own geocoder: no key, no billing.
  /// Best with a name and an area, like "Cult Indiranagar".
  static Future<List<PickedPlace>> search(String query) async {
    final values = await _channel.invokeMethod<List<dynamic>>('geocode', {
      'query': query,
    });
    return [
      for (final value in values ?? const [])
        PickedPlace.fromMap(value as Map),
    ];
  }
}
