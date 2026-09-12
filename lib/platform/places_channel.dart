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
}
