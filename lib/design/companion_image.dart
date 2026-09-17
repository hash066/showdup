import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../models/pet.dart';
import 'companion.dart';

/// Renders the companion to a PNG for native surfaces like the bubble, so
/// Android shows the same drawing as the app. Files are cached per look.
class CompanionImage {
  const CompanionImage._();

  static const _pixels = 168;
  static final _pending = <String, Future<String?>>{};

  static Future<String?> path(MascotId mascot, CompanionMood mood) {
    final name = '${mascot.wire}-${mood.name}';
    return _pending[name] ??= _render(
      name,
      mascot,
      mood,
    ).whenComplete(() => _pending.remove(name));
  }

  static Future<String?> _render(
    String name,
    MascotId mascot,
    CompanionMood mood,
  ) async {
    try {
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/companion',
      );
      final file = File('${dir.path}/$name.png');
      if (await file.exists()) return file.path;
      await dir.create(recursive: true);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size.square(_pixels * 1.0);
      CompanionPainter(mascot, mood).paint(canvas, size);
      final image = await recorder.endRecording().toImage(_pixels, _pixels);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return null;
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return file.path;
    } catch (_) {
      // The bubble falls back to the mark.
      return null;
    }
  }
}
