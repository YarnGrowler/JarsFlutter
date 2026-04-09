import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/achievement_unlock_toast.dart';

export '../models/achievement_unlock_toast.dart';

final achievementUnlockToastProvider =
    StateProvider<List<AchievementUnlockToast>?>((ref) => null);
