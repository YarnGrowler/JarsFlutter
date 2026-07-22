import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../core/jars_clock.dart';
import '../core/jars_timezone.dart';
import '../core/league_config.dart';
import '../core/siege_config.dart';
import '../models/exercise_log.dart';
import '../models/league.dart';
import '../models/room.dart';
import '../models/siege.dart';
import 'assault_generator.dart';
import 'league_service.dart';
import 'league_simulator.dart';
import 'siege_engine.dart';
import 'supabase_service.dart';

/// Siege outcomes for a season: one entry per completed week, plus the
/// in-progress week's full state for the UI.
class SeasonSieges {
  final List<bool?> outcomes; // completed weeks: held?
  final List<SiegeResult?> results;
  final SiegeWeekState? current;
  const SeasonSieges({
    required this.outcomes,
    required this.results,
    this.current,
  });
}

/// Real-data orchestration for Siege (client-computed, deterministic — like
/// the league). Supply comes from real logged workouts; allocations are
/// shared `__SIEGE__|` event rows in `exercise_logs` (append-only, covered by
/// existing RLS/realtime, auto-excluded from all points math by the `^__`
/// filters). Only the W/L result is persisted — via the existing league
/// mechanism. No new SQL.
class SiegeService {
  static final _db = SupabaseService.client;

  /// Days into the current siege week that have fully resolved (Chicago days;
  /// day d resolves once the calendar passes it).
  static int currentDayIndex(int absWeek) {
    final today = JarsClock.instance.todayChicago();
    final weekStart = LeagueService.weekStartDate(absWeek);
    return today.difference(weekStart).inDays.clamp(0, SiegeConfig.instance.days);
  }

  static int _dayIndexForUtc(DateTime utc, DateTime weekStartDate) {
    JarsTimezone.ensureInitialized();
    final loc = tz.getLocation(JarsTimezone.locationName);
    final chi = tz.TZDateTime.from(utc, loc);
    final date = DateTime(chi.year, chi.month, chi.day);
    return date.difference(weekStartDate).inDays;
  }

  /// Commit supply from the shared bank onto a (day, front) cell. Written as a
  /// `__SIEGE__|` event row so every crewmate's engine sees the same input.
  static Future<void> allocate({
    required String roomId,
    required int day,
    required int front,
    required double amount,
  }) async {
    final userId = SupabaseService.currentUserId!;
    final payload = jsonEncode({
      'k': 'alloc',
      'd': day,
      'f': front,
      'a': double.parse(amount.toStringAsFixed(1)),
    });
    await _db.from('exercise_logs').insert({
      'room_id': roomId,
      'user_id': userId,
      'exercise_id': null,
      'exercise_name': '${ExerciseLog.kSiegeEventPrefix}$payload',
      'count': 0,
      'weight': 0,
      'points_earned': 0,
    });
  }

  /// Compute siege outcomes for [seasonIndex]: resolves every completed week
  /// and (optionally) the in-progress one, from real logs + shared alloc rows.
  static Future<SeasonSieges> computeSeasonSieges({
    required Room room,
    required LeagueDivision division,
    required int seasonIndex,
    required int seasonStartWeekAbs, // room-anchored (absolute weeks)
    required int completedWeeks,
    required bool includeCurrent,
    required List<int> yourWeekly,
    required int activeMembers,
    required double anchorPerMember,
    required LeagueSimulator sim,
  }) async {
    final cfg = SiegeConfig.instance;
    final mw = LeagueConfig.instance.matchweeks;
    final startAbs = seasonStartWeekAbs;
    final weeksToBuild =
        (includeCurrent ? completedWeeks + 1 : completedWeeks).clamp(0, mw);
    if (weeksToBuild <= 0) {
      return const SeasonSieges(outcomes: [], results: [], current: null);
    }

    final fromUtc = LeagueService.weekStartUtc(startAbs);
    final toUtc = LeagueService.weekStartUtc(startAbs + weeksToBuild);

    // Real workouts → supply events, bucketed per week.
    final logRows = await _db
        .from('exercise_logs')
        .select('user_id, points_earned, created_at, exercise_name')
        .eq('room_id', room.id)
        .gte('created_at', fromUtc.toIso8601String())
        .lt('created_at', toUtc.toIso8601String())
        .not('exercise_name', 'match', r'^__');

    // Shared allocation events.
    final allocRows = await _db
        .from('exercise_logs')
        .select('id, user_id, exercise_name, created_at')
        .eq('room_id', room.id)
        .gte('created_at', fromUtc.toIso8601String())
        .lt('created_at', toUtc.toIso8601String())
        .like('exercise_name', '${ExerciseLog.kSiegeEventPrefix}%');

    final supplyByWeek = <int, List<SupplyEvent>>{};
    for (final r in logRows) {
      final createdRaw = r['created_at'] as String?;
      final uid = r['user_id'] as String?;
      if (createdRaw == null || uid == null) continue;
      final created = DateTime.parse(createdRaw).toUtc();
      final absWeek = LeagueService.weekAbsForUtc(created);
      final w = absWeek - startAbs;
      if (w < 0 || w >= weeksToBuild) continue;
      final weekStartDate = LeagueService.weekStartDate(absWeek);
      final pts = (r['points_earned'] as num?)?.toDouble() ?? 0;
      if (pts <= 0) continue;
      supplyByWeek.putIfAbsent(w, () => []).add(SupplyEvent(
            userId: uid,
            amount: pts * cfg.supplyPerPoint,
            dayIndex: _dayIndexForUtc(created, weekStartDate),
            at: created,
          ));
    }

    final allocByWeek = <int, List<SiegeAllocation>>{};
    for (final r in allocRows) {
      final createdRaw = r['created_at'] as String?;
      final name = r['exercise_name'] as String?;
      final uid = r['user_id'] as String?;
      final id = r['id']?.toString() ?? '';
      if (createdRaw == null || name == null || uid == null) continue;
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(
                name.substring(ExerciseLog.kSiegeEventPrefix.length))
            as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (payload['k'] != 'alloc') continue;
      final created = DateTime.parse(createdRaw).toUtc();
      final absWeek = LeagueService.weekAbsForUtc(created);
      final w = absWeek - startAbs;
      if (w < 0 || w >= weeksToBuild) continue;
      final weekStartDate = LeagueService.weekStartDate(absWeek);
      allocByWeek.putIfAbsent(w, () => []).add(SiegeAllocation(
            userId: uid,
            day: (payload['d'] as num?)?.toInt() ?? -1,
            front: (payload['f'] as num?)?.toInt() ?? -1,
            amount: (payload['a'] as num?)?.toDouble() ?? 0,
            createdDayIndex: _dayIndexForUtc(created, weekStartDate),
            at: created,
            id: id,
          ));
    }

    final gen = AssaultGenerator(cfg);
    final engine = SiegeEngine(cfg);
    final outcomes = <bool?>[];
    final results = <SiegeResult?>[];
    SiegeWeekState? current;

    for (var w = 0; w < weeksToBuild; w++) {
      final live = sim.matchForWeek(
        roomId: room.id,
        division: division,
        seasonIndex: seasonIndex,
        week: w,
        yourWeeklyPoints: yourWeekly,
        yourActiveMembers: activeMembers,
        anchorPerMember: anchorPerMember,
      );
      final isCurrent = includeCurrent && w == completedWeeks;
      if (live == null) {
        if (!isCurrent) {
          outcomes.add(null);
          results.add(null);
        }
        continue;
      }
      final total = live.opponentScore.toDouble();
      final plan = gen.generate(
        roomId: room.id,
        divisionId: division.id,
        seasonIndex: seasonIndex,
        weekIndex: w,
        opponentId: live.opponent.id,
        opponentName: live.opponent.name,
        totalAssault: total < 1 ? 1 : total,
      );
      final state = engine.resolveWeek(
        plan: plan,
        supply: supplyByWeek[w] ?? const [],
        allocations: allocByWeek[w] ?? const [],
        daysResolved: isCurrent ? currentDayIndex(startAbs + w) : cfg.days,
      );
      if (isCurrent) {
        current = state;
      } else {
        outcomes.add(state.result?.won);
        results.add(state.result);
      }
    }

    return SeasonSieges(outcomes: outcomes, results: results, current: current);
  }
}
