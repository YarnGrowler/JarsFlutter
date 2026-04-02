import 'supabase_service.dart';
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
    bool supportsWeight = false,
    double? weightThreshold,
    double? weightMultiplier,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final data = await _db.from('exercises').insert({
      'room_id': roomId,
      'name': name,
      'points': points,
      'icon': icon,
      'category': category,
      'supports_weight': supportsWeight,
      'weight_threshold': weightThreshold,
      'weight_multiplier': weightMultiplier,
      'created_by': userId,
    }).select().single();

    return Exercise.fromJson(data);
  }

  static Future<void> deleteExercise(String exerciseId) async {
    await _db.from('exercises').delete().eq('id', exerciseId);
  }
}
