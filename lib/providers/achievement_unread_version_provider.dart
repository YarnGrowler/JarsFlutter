import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Incremented after a log when the achievements Edge function reported new unlocks,
/// so the Ranks tab can refresh its red-dot query.
final achievementUnreadVersionProvider = StateProvider<int>((ref) => 0);
