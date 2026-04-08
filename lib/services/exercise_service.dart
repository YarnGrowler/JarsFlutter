import 'supabase_service.dart';
import '../core/count_unit.dart';
import '../models/exercise.dart';

class ExerciseService {
  static final _db = SupabaseService.client;

  static Future<List<Exercise>> getRoomExercises(String roomId) async {
    final rows = await _db
        .from('exercises')
        .select()
        .eq('room_id', roomId)
        .order('category')
        .order('name');

    return rows
        .map((r) => Exercise.fromJson(r))
        .toList();
  }

  static Future<Exercise> createCustomExercise({
    required String roomId,
    required String name,
    required double points,
    required String icon,
    required String category,
    CountUnit countUnit = CountUnit.reps,
    TimePointsMode timePointsMode = TimePointsMode.perMinute,
    bool timerUi = false,
    bool supportsWeight = false,
    double? weightThreshold,
    double? weightMultiplier,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final usesTime =
        countUnit == CountUnit.seconds || countUnit == CountUnit.minutes;
    final tpm = countUnit == CountUnit.seconds ? timePointsMode : null;
    final insert = <String, dynamic>{
      'room_id': roomId,
      'name': name,
      'points': points,
      'icon': icon,
      'category': category,
      'supports_weight': supportsWeight,
      'weight_threshold': supportsWeight ? weightThreshold : null,
      'weight_multiplier': supportsWeight ? weightMultiplier : null,
      'created_by': userId,
      'count_unit': countUnit.name,
      'uses_time': usesTime,
      'timer_ui': countUnit == CountUnit.seconds && timerUi,
    };
    if (tpm != null) {
      insert['time_points_mode'] = timePointsModeToJson(tpm);
    } else {
      insert['time_points_mode'] = null;
    }
    final data = await _db.from('exercises').insert(insert).select().single();

    return Exercise.fromJson(data);
  }

  static Future<void> deleteExercise(String exerciseId) async {
    await _db.from('exercises').delete().eq('id', exerciseId);
  }
}
