import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/controller.dart';

final appProvider = ChangeNotifierProvider<AppController>(
  (ref) => throw StateError('App session not initialized'),
);
