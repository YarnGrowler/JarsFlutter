import 'dart:convert';
import 'dart:math' as math;

import '../core/debug_bots.dart';
import '../core/jars_clock.dart';
import '../core/jars_timezone.dart';
import '../core/seeded_rng.dart';
import '../core/siege_config.dart';
import '../models/exercise_log.dart';
import '../models/league.dart';
import '../models/room.dart';
import '../models/siege.dart';
import 'debug_bot_service.dart';
import 'league_service.dart';
import 'supabase_service.dart';

/// Debug-only time machine that drives the REAL game. Bots (real accounts from
/// patch 47) log real workouts via [DebugBotService]; defenses are real
/// `__SIEGE__|` allocation rows; "skip" advances the persisted
/// [DebugClockStore]. The live Siege/League/home screens all move.
///
/// Ordering rule (this was the freeze bug): **the clock always advances**, even
/// if a bot insert throws — every side effect is best-effort and swallowed, and
/// the advance runs unconditionally at the end.
class SiegeDevDriver {
  static final _db = SupabaseService.client;

  /// Small catalog of believable bot workouts as (name, points-per-rep).
  static const List<(String, double)> _workouts = [
    ('Push-ups', 2.0),
    ('Squats', 2.0),
    ('Sit-ups', 1.0),
    ('Pull-ups', 5.0),
    ('Lunges', 2.0),
    ('Burpees', 4.0),
    ('Kettlebell swings', 3.0),
  ];

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Skip one simulated day: (in-season) bots train + tonight's wave gets
  /// auto-defended, then the clock advances so the wave resolves. Always
  /// advances the clock. Returns a short status line.
  static Future<String> skipDay(Room room, {bool autoDefend = true}) async {
    final dayDate = JarsClock.instance.todayChicago();
    var botPts = 0;
    var deployed = 0;
    var inSiege = false;

    try {
      final table = await LeagueService.getLeague(room);
      final siege = table.siege;
      inSiege = !table.preseason && siege != null && siege.result == null;
      if (inSiege) {
        botPts = await _logCrewForDay(room, dayDate);
        if (autoDefend) deployed = await _autoDefendToday(room, dayDate);
      }
    } catch (_) {/* never let a read/write failure freeze time */}

    await DebugClockStore.advance(1); // <-- unconditional: time always moves

    if (!inSiege) return '📅 Advanced a day — campaign not started yet';
    final parts = <String>[
      if (botPts > 0) '🏋️ crew logged $botPts pts',
      if (deployed > 0) '🛡 deployed $deployed supply',
      '🌙 the wave resolved',
    ];
    return parts.join(' · ');
  }

  /// One tap: fast-forward into a live siege that already has a few resolved
  /// waves, so you immediately see the full battlefield — supplied and winnable.
  /// Forward-only: it never marches across many losses; it rolls to a FRESH
  /// in-season week and stops mid-battle.
  static Future<String> jumpIntoLiveSiege(Room room) async {
    // Fresh slate every jump: clear prior sim data + reset the clock to today,
    // so a polluted/fallen room can't drag the new battle down.
    await _wipeSimData(room);
    await DebugClockStore.set(0);

    // Ensure a logging crew. Bots (patch 47) are a bonus; the dev player always
    // supplies the siege via [skipDay] even if the patch isn't applied.
    try {
      await DebugBotService.addBotsToRoom(room.id);
      if (DebugBots.roster.isEmpty) {
        for (final p in BotMember.presets) {
          await DebugBots.toggle(p);
        }
      }
    } catch (_) {/* no patch 47 — dev player still fuels the siege */}

    var guard = 0;
    while (guard++ < 20) {
      LeagueTable table;
      try {
        table = await LeagueService.getLeague(room);
      } catch (_) {
        break;
      }
      final s = table.preseason ? null : table.siege;
      // Reached a live, mid-battle week → done.
      if (s != null && s.result == null && s.daysResolved >= 3) break;
      // Prep → Monday; a decided week → its remaining days then next Monday;
      // early days → forward. skipDay only logs the crew on live in-season days.
      await skipDay(room, autoDefend: true);
    }
    return '⚔️ Jumped into a live siege';
  }

  /// Skip to the next Monday (finish the current siege week or leave prep).
  static Future<String> finishWeek(Room room, {bool autoDefend = true}) async {
    final today = JarsClock.instance.todayChicago();
    final weekAbs = LeagueService.mondayWeekAbs(today);
    final startAbs = LeagueService.roomStartWeekAbs(room);
    final int steps;
    if (weekAbs < startAbs) {
      steps = LeagueService.weekStartDate(startAbs).difference(today).inDays;
    } else {
      steps = 7 - today.difference(LeagueService.weekStartDate(weekAbs)).inDays;
    }
    final n = steps.clamp(1, 7);
    for (var i = 0; i < n; i++) {
      await skipDay(room, autoDefend: autoDefend);
    }
    return 'Skipped $n ${n == 1 ? 'day' : 'days'} to Monday';
  }

  /// Delete all simulated data from the room (bot members/scores/logs, siege
  /// allocations, and the dev player's future-dated sim workouts). Leaves the
  /// roster + clock alone — callers decide.
  static Future<void> _wipeSimData(Room room) async {
    try {
      await DebugBotService.removeBots(room.id);
    } catch (_) {}
    try {
      await _db
          .from('exercise_logs')
          .delete()
          .eq('room_id', room.id)
          .like('exercise_name', '${ExerciseLog.kSiegeEventPrefix}%');
    } catch (_) {}
    // Legacy: clear any old-style "🤖 " bot rows from before patch 47.
    try {
      await _db
          .from('exercise_logs')
          .delete()
          .eq('room_id', room.id)
          .like('exercise_name', '🤖 %');
    } catch (_) {}
    // Wipe the dev player's future-dated sim workouts (real logs are in the
    // past, so a "created_at in the future" filter only catches sim data).
    try {
      final uid = SupabaseService.currentUserId;
      if (uid != null) {
        await _db
            .from('exercise_logs')
            .delete()
            .eq('room_id', room.id)
            .eq('user_id', uid)
            .gt('created_at', DateTime.now().toUtc().toIso8601String());
      }
    } catch (_) {}
  }

  /// Back to real time: wipe sim data, clear the roster, and zero the clock.
  static Future<void> resetAll(Room room) async {
    await _wipeSimData(room);
    await DebugBots.clear();
    await DebugClockStore.set(0);
  }

  // ── internals ────────────────────────────────────────────────────────────
  /// The dev crew's real workouts for [dayDate] (deterministic per room+date).
  /// The dev player always logs (RLS-valid, no patch needed) so the siege has
  /// supply; bots log via patch 47. Best-effort. Returns total points logged.
  static Future<int> _logCrewForDay(Room room, DateTime dayDate) async {
    var total = 0;
    final noon =
        JarsTimezone.startOfChicagoDayUtc(dayDate).add(const Duration(hours: 12));

    // The dev player trains — supply exists even before any bots / patch 47.
    final devRng =
        SeededRng(seedFromParts([room.id, 'dev-player', _ymd(dayDate)]));
    final devPts =
        (kDevPlayerDailyPoints + _gauss(devRng) * 55).clamp(60.0, 700.0);
    final (dn, dppr) = _workouts[devRng.next() % _workouts.length];
    final dcount = math.max(1, (devPts / dppr).round());
    try {
      await _db.from('exercise_logs').insert({
        'room_id': room.id,
        'user_id': SupabaseService.currentUserId,
        'exercise_id': null,
        'exercise_name': dn,
        'count': dcount,
        'weight': 0,
        'points_earned': dcount * dppr,
        'created_at': noon.toIso8601String(),
      });
      total += (dcount * dppr).round();
    } catch (_) {}

    for (var i = 0; i < DebugBots.roster.length; i++) {
      final bot = DebugBots.roster[i];
      final uuid = DebugBots.uuidFor(bot);
      if (uuid == null) continue; // patch 47 not applied for this bot
      final rng = SeededRng(seedFromParts([room.id, bot.id, _ymd(dayDate)]));
      if (rng.unit() >= bot.activeProbability) continue; // rest day
      var pts = bot.meanDailyPoints + _gauss(rng) * bot.variance;
      if (pts < 1) continue;
      final (name, ppr) = _workouts[rng.next() % _workouts.length];
      final count = math.max(1, (pts / ppr).round());
      final points = count * ppr;
      try {
        await DebugBotService.botLog(
          roomId: room.id,
          botUuid: uuid,
          exerciseName: name,
          count: count,
          points: points,
          createdAt: noon.add(Duration(minutes: i)),
        );
        total += points.round();
      } catch (_) {/* keep going; time still advances */}
    }
    return total;
  }

  /// Auto-defend today's wave with the current bank, proportional to the gaps.
  static Future<int> _autoDefendToday(Room room, DateTime dayDate) async {
    try {
      final table = await LeagueService.getLeague(room);
      final siege = table.siege;
      if (siege == null || siege.result != null) return 0;
      final d = siege.daysResolved;
      if (d >= SiegeConfig.instance.days) return 0;
      final atk = siege.plan.attack[d];
      final def = siege.defense[d];
      final gaps = <double>[];
      var totalGap = 0.0;
      for (var f = 0; f < atk.length; f++) {
        final g = math.max(0.0, atk[f] - def[f]);
        gaps.add(g);
        totalGap += g;
      }
      final bank = siege.bankRemaining;
      if (totalGap < 1 || bank < 1) return 0;
      final scale = bank >= totalGap ? 1.0 : bank / totalGap;
      final at =
          JarsTimezone.startOfChicagoDayUtc(dayDate).add(const Duration(hours: 13));
      var deployed = 0;
      for (var f = 0; f < gaps.length; f++) {
        final amt = gaps[f] * scale;
        if (amt < 1) continue;
        try {
          await _db.from('exercise_logs').insert({
            'room_id': room.id,
            'user_id': SupabaseService.currentUserId,
            'exercise_id': null,
            'exercise_name': '${ExerciseLog.kSiegeEventPrefix}${jsonEncode({
                  'k': 'alloc',
                  'd': d,
                  'f': f,
                  'a': double.parse(amt.toStringAsFixed(1)),
                })}',
            'count': 0,
            'weight': 0,
            'points_earned': 0,
            'created_at': at.add(Duration(minutes: f)).toIso8601String(),
          });
          deployed += amt.round();
        } catch (_) {}
      }
      return deployed;
    } catch (_) {
      return 0;
    }
  }

  /// Deterministic normal(0,1) via Box-Muller on the seeded RNG.
  static double _gauss(SeededRng rng) {
    var u1 = rng.unit();
    if (u1 < 1e-9) u1 = 1e-9;
    final u2 = rng.unit();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
