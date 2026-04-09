import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hints from Edge `process-achievements` after a log; consumed by [RoomScreen] for a snack bar.
final achievementPostLogHintsProvider = StateProvider<List<String>?>((ref) => null);
