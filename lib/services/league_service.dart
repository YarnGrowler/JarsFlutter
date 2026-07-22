import 'dart:async';

import 'package:timezone/timezone.dart' as tz;

import '../core/debug_bots.dart';
import '../core/debug_tools.dart';
import '../core/jars_clock.dart';
import '../core/jars_timezone.dart';
import '../core/league_config.dart';
import '../core/siege_config.dart';
import '../models/exercise_log.dart';
import '../models/league.dart';
import '../models/room.dart';
import '../models/siege.dart';
import 'league_simulator.dart';
import 'siege_service.dart';
import 'supabase_service.dart';

/// Orchestrates the league: turns the room's real weekly logged points into a
/// team, runs the deterministic [LeagueSimulator] for the AI opponents, and
/// persists only the room's current division + season (promotion/relegation).
///
/// Degrades gracefully: if patch 46 (`room_leagues` / `advance_room_league`) is
/// not applied, the room simply sits in the lowest division and everything else
/// still works — same approach as the crew jar.
class LeagueService {
  static final _db = SupabaseService.client;
  static final _sim = LeagueSimulator();

  /// Fixed reference Monday (2024-01-01 is a Monday) for deterministic indexing.
  static final DateTime _epochMonday = DateTime(2024, 1, 1);

  static int mondayWeekAbs(DateTime chicagoDate) {
    final monday =
        chicagoDate.subtract(Duration(days: chicagoDate.weekday - 1));
    return monday.difference(_epochMonday).inDays ~/ 7;
  }

  static DateTime weekStartUtc(int weekAbs) {
    final monday = _epochMonday.add(Duration(days: weekAbs * 7));
    return JarsTimezone.startOfChicagoDayUtc(monday);
  }

  /// The Chicago calendar date (y/m/d) a given absolute week starts on.
  static DateTime weekStartDate(int weekAbs) =>
      _epochMonday.add(Duration(days: weekAbs * 7));

  /// The absolute week a room's campaign starts: the Monday of creation if the
  /// room was born on a Monday, otherwise the following Monday. Every crew
  /// starts at Matchweek 1, Day 1 of a full week — no inherited losses from
  /// weeks before the room existed.
  static int roomStartWeekAbs(Room room) {
    JarsTimezone.ensureInitialized();
    final loc = tz.getLocation(JarsTimezone.locationName);
    final chi = tz.TZDateTime.from(room.createdAt.toUtc(), loc);
    final createdDate = DateTime(chi.year, chi.month, chi.day);
    final createdWeek = mondayWeekAbs(createdDate);
    return createdDate == weekStartDate(createdWeek)
        ? createdWeek
        : createdWeek + 1;
  }

  static int weekAbsForUtc(DateTime utc) {
    final loc = tz.getLocation(JarsTimezone.locationName);
    final chi = tz.TZDateTime.from(utc, loc);
    return mondayWeekAbs(DateTime(chi.year, chi.month, chi.day));
  }

  /// Build the current league snapshot for [room].
  static Future<LeagueTable> getLeague(Room room) async {
    JarsTimezone.ensureInitialized();
    final cfg = LeagueConfig.instance;
    final mw = cfg.matchweeks;

    final today = JarsClock.instance.todayChicago();
    final weekAbs = mondayWeekAbs(today);
    final startAbs = roomStartWeekAbs(room);
    final relWeek = weekAbs - startAbs;

    // Preparation phase: room born mid-week — the campaign starts Monday.
    // Logs made now are real (they feed the anchor), so week 1 is calibrated.
    if (relWeek < 0) {
      final daysUntil = weekStartDate(startAbs).difference(today).inDays;
      final activeMembers = await _activeMembers(room.id);
      final table = _sim.build(
        roomId: room.id,
        yourTeamName: room.name,
        division: cfg.divisionByIndex(0),
        seasonIndex: 0,
        completedWeeks: 0,
        yourWeeklyPoints: const [0],
        yourActiveMembers: activeMembers,
        anchorPerMember:
            cfg.balance.fallbackPerMember ?? (7.0 * room.streakMinimum),
      );
      return table.asPreseason(daysUntil);
    }

    final currentSeason = relWeek ~/ mw;
    final weekInSeason = relWeek % mw;
    final seasonStartWeekAbs = startAbs + currentSeason * mw;

    // One query: this season + a trailing window for the anchor.
    final lookbackWeeks = mw + cfg.balance.anchorTrailingWeeks + 1;
    final fromUtc = weekStartUtc(weekAbs - lookbackWeeks);
    final byWeek = await _teamPointsByWeek(room.id, fromUtc);
    final activeMembers = await _activeMembers(room.id);
    final anchorPerMember = _anchorPerMember(byWeek, weekAbs, activeMembers, room, cfg);

    // Your real points for each week of this season (last entry = live week).
    final yourWeekly = <int>[
      for (var w = 0; w <= weekInSeason; w++)
        (byWeek[seasonStartWeekAbs + w] ?? 0).round(),
    ];

    final divIndex = await _resolveDivision(
      room: room,
      currentSeason: currentSeason,
      mw: mw,
      activeMembers: activeMembers,
      anchorPerMember: anchorPerMember,
      cfg: cfg,
    );

    // Siege mode: resolve this season's sieges from real logs + shared
    // allocation rows; their outcomes replace score-comparison for YOUR
    // fixtures. Failure degrades gracefully to the classic score model.
    SeasonSieges? sieges;
    if (SiegeConfig.instance.enabled) {
      try {
        sieges = await SiegeService.computeSeasonSieges(
          room: room,
          division: cfg.divisionByIndex(divIndex),
          seasonIndex: currentSeason,
          seasonStartWeekAbs: seasonStartWeekAbs,
          completedWeeks: weekInSeason,
          includeCurrent: true,
          yourWeekly: yourWeekly,
          activeMembers: activeMembers,
          anchorPerMember: anchorPerMember,
          sim: _sim,
        );
      } catch (_) {
        sieges = null;
      }
    }

    final table = _sim.build(
      roomId: room.id,
      yourTeamName: room.name,
      division: cfg.divisionByIndex(divIndex),
      seasonIndex: currentSeason,
      completedWeeks: weekInSeason,
      yourWeeklyPoints: yourWeekly,
      yourActiveMembers: activeMembers,
      anchorPerMember: anchorPerMember,
      yourOutcomes: sieges?.outcomes,
    ).withSiege(sieges?.current);
    unawaited(_maybeAnnounceResolvedWeek(
      room: room,
      table: table,
      yourWeekly: yourWeekly,
      activeMembers: activeMembers,
      anchorPerMember: anchorPerMember,
      siegeResults: sieges?.results,
    ));
    return table;
  }

  // ── league event announcement (once per resolved week) ──────────────────────
  static Future<void> _maybeAnnounceResolvedWeek({
    required Room room,
    required LeagueTable table,
    required List<int> yourWeekly,
    required int activeMembers,
    required double anchorPerMember,
    List<SiegeResult?>? siegeResults,
  }) async {
    final cfg = LeagueConfig.instance;
    if (cfg.mode != LeagueMode.fixtures) return;
    final done = table.completedWeeks;
    if (done < 1) return;
    final wk = done - 1;

    final match = _sim.matchForWeek(
      roomId: room.id,
      division: table.division,
      seasonIndex: table.seasonIndex,
      week: wk,
      yourWeeklyPoints: yourWeekly,
      yourActiveMembers: activeMembers,
      anchorPerMember: anchorPerMember,
    );
    if (match == null) return;
    final dedupeWeekAbs =
        roomStartWeekAbs(room) + table.seasonIndex * cfg.matchweeks + wk;

    final you = match.yourScore;
    final opp = match.opponentScore;
    final verb = you > opp ? 'beat' : (you == opp ? 'drew with' : 'lost to');

    final outcomes = siegeResults?.map((r) => r?.won).toList();
    final prev = _sim.build(
      roomId: room.id,
      yourTeamName: room.name,
      division: table.division,
      seasonIndex: table.seasonIndex,
      completedWeeks: wk,
      yourWeeklyPoints: yourWeekly,
      yourActiveMembers: activeMembers,
      anchorPerMember: anchorPerMember,
      yourOutcomes: outcomes?.take(wk).toList(),
    );
    final posNow = table.yourRow?.position ?? 0;
    final posPrev = prev.yourRow?.position ?? posNow;
    var move = '';
    if (posNow > 0 && posNow < posPrev) {
      move = ' — up to $posNow${_ord(posNow)}';
    } else if (posNow > posPrev) {
      move = ' — slipped to $posNow${_ord(posNow)}';
    }
    final sr = (siegeResults != null && wk < siegeResults.length)
        ? siegeResults[wk]
        : null;
    final body = sr != null
        ? (sr.won
            ? '🛡 Siege held vs ${match.opponent.name} — '
                '${sr.integrityRemaining.round()} integrity left$move'
            : '💥 Stronghold fell to ${match.opponent.name} on day '
                '${(sr.breachDay ?? SiegeConfig.instance.days - 1) + 1}$move')
        : 'League: you $verb ${match.opponent.name} $you–$opp$move';

    try {
      final sent = await _db.rpc('notify_league_event', params: {
        'p_room_id': room.id,
        'p_week_index': dedupeWeekAbs,
        'p_kind': 'result',
        'p_body': body,
      });
      if (sent == true) {
        final uid = SupabaseService.currentUserId;
        if (uid != null) {
          await _db.from('exercise_logs').insert({
            'room_id': room.id,
            'user_id': uid,
            'exercise_id': null,
            'exercise_name': '${ExerciseLog.kLeaguePrefix}$body',
            'count': 0,
            'weight': 0,
            'points_earned': 0,
          });
        }
      }
    } catch (_) {}
  }

  static String _ord(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  // ── data helpers ─────────────────────────────────────────────────────────────
  static Future<Map<int, double>> _teamPointsByWeek(
      String roomId, DateTime fromUtc) async {
    final rows = await _db
        .from('exercise_logs')
        .select('points_earned, created_at, exercise_name')
        .eq('room_id', roomId)
        .gte('created_at', fromUtc.toIso8601String())
        .not('exercise_name', 'match', r'^__');
    final byWeek = <int, double>{};
    for (final r in rows) {
      final createdRaw = r['created_at'] as String?;
      if (createdRaw == null) continue;
      final wk = weekAbsForUtc(DateTime.parse(createdRaw).toUtc());
      final pts = (r['points_earned'] as num?)?.toDouble() ?? 0;
      byWeek[wk] = (byWeek[wk] ?? 0) + pts;
    }
    return byWeek;
  }

  static Future<int> _activeMembers(String roomId) async {
    final since = JarsTimezone.startOfChicagoDayUtc(
        JarsClock.instance.todayChicago().subtract(const Duration(days: 14)));
    final rows = await _db
        .from('exercise_logs')
        .select('user_id')
        .eq('room_id', roomId)
        .gte('created_at', since.toIso8601String())
        .not('exercise_name', 'match', r'^__');
    final users = <String>{};
    for (final r in rows) {
      final uid = r['user_id'] as String?;
      if (uid != null) users.add(uid);
    }
    final n = users.isEmpty ? 1 : users.length;
    // Debug bots all log under the dev user's id, so count them as members —
    // otherwise a 3-bot crew reads as a 1-person team and every knob mis-scales.
    if (kDebugTools) return n + DebugBots.roster.length;
    return n;
  }

  /// Average team points over the last few *active* weeks, per active member.
  /// Rest weeks (0 points) are skipped so a break doesn't tank your baseline.
  static double _anchorPerMember(Map<int, double> byWeek, int weekAbs,
      int activeMembers, Room room, LeagueConfig cfg) {
    final vals = <double>[];
    for (var i = 1; i <= cfg.balance.anchorTrailingWeeks; i++) {
      final v = byWeek[weekAbs - i] ?? 0;
      if (v > 0) vals.add(v);
    }
    if (vals.isEmpty) {
      final base = cfg.balance.fallbackPerMember ?? (7.0 * room.streakMinimum);
      // Dev builds with no history yet: calibrate week 1 to the dev crew's
      // expected output (dev player + bots) so the first siege is competitive
      // and defensible — not a trivially small (or unwinnable) assault.
      if (kDebugTools) {
        final members = activeMembers < 1 ? 1 : activeMembers;
        final perMember = DebugBots.crewExpectedWeekly() / members;
        return perMember > base ? perMember : base;
      }
      return base;
    }
    final avg = vals.reduce((a, b) => a + b) / vals.length;
    return avg / (activeMembers < 1 ? 1 : activeMembers);
  }

  // ── division / season persistence (idempotent, graceful) ─────────────────────
  static Future<int> _resolveDivision({
    required Room room,
    required int currentSeason,
    required int mw,
    required int activeMembers,
    required double anchorPerMember,
    required LeagueConfig cfg,
  }) async {
    try {
      final rows = await _db
          .from('room_leagues')
          .select('division_index, season_index')
          .eq('room_id', room.id)
          .limit(1);

      var storedDiv = 0;
      var storedSeason = currentSeason;
      final exists = rows.isNotEmpty;
      if (exists) {
        storedDiv = (rows.first['division_index'] as num?)?.toInt() ?? 0;
        storedSeason = (rows.first['season_index'] as num?)?.toInt() ?? currentSeason;
      }

      if (exists && storedSeason >= currentSeason) return storedDiv;

      int newDiv;
      if (!exists) {
        newDiv = 0; // new team starts in the lowest division
      } else if (storedSeason == currentSeason - 1) {
        newDiv = await _resolvePreviousSeason(
            room, storedDiv, storedSeason, mw, activeMembers, anchorPerMember, cfg);
      } else {
        newDiv = storedDiv; // multi-season gap: hold division (no replay)
      }

      // Persist; RPC applies only if p_season_index > stored (DB-guarded).
      await _db.rpc('advance_room_league', params: {
        'p_room_id': room.id,
        'p_division_index': newDiv,
        'p_season_index': currentSeason,
      });
      return newDiv;
    } catch (_) {
      return 0; // patch 46 not applied yet → default division
    }
  }

  /// Determine promotion/relegation from the finished previous season's table.
  static Future<int> _resolvePreviousSeason(Room room, int divIndex, int season,
      int mw, int activeMembers, double anchorPerMember, LeagueConfig cfg) async {
    final startWeekAbs = roomStartWeekAbs(room) + season * mw;
    final fromUtc = weekStartUtc(startWeekAbs);
    final toUtc = weekStartUtc(startWeekAbs + mw);
    final rows = await _db
        .from('exercise_logs')
        .select('points_earned, created_at, exercise_name')
        .eq('room_id', room.id)
        .gte('created_at', fromUtc.toIso8601String())
        .lt('created_at', toUtc.toIso8601String())
        .not('exercise_name', 'match', r'^__');
    final byWeek = <int, double>{};
    for (final r in rows) {
      final createdRaw = r['created_at'] as String?;
      if (createdRaw == null) continue;
      final wk = weekAbsForUtc(DateTime.parse(createdRaw).toUtc());
      byWeek[wk] = (byWeek[wk] ?? 0) + ((r['points_earned'] as num?)?.toDouble() ?? 0);
    }
    final weekly = <int>[
      for (var w = 0; w < mw; w++) (byWeek[startWeekAbs + w] ?? 0).round(),
    ];

    // Under siege mode, last season's promotion/relegation must be decided by
    // the same siege outcomes the crew watched all season — not raw scores.
    List<bool?>? outcomes;
    if (SiegeConfig.instance.enabled) {
      try {
        final s = await SiegeService.computeSeasonSieges(
          room: room,
          division: cfg.divisionByIndex(divIndex),
          seasonIndex: season,
          seasonStartWeekAbs: startWeekAbs,
          completedWeeks: mw,
          includeCurrent: false,
          yourWeekly: weekly,
          activeMembers: activeMembers,
          anchorPerMember: anchorPerMember,
          sim: _sim,
        );
        outcomes = s.outcomes;
      } catch (_) {
        outcomes = null;
      }
    }

    final table = _sim.build(
      roomId: room.id,
      yourTeamName: room.name,
      division: cfg.divisionByIndex(divIndex),
      seasonIndex: season,
      completedWeeks: mw,
      yourWeeklyPoints: weekly,
      yourActiveMembers: activeMembers,
      anchorPerMember: anchorPerMember,
      yourOutcomes: outcomes,
    );
    final pos = table.yourRow?.position ?? cfg.teamsPerLeague;

    if (pos <= cfg.promoteCount && divIndex < cfg.divisions.length - 1) {
      return divIndex + 1;
    }
    if (pos > cfg.teamsPerLeague - cfg.relegateCount && divIndex > 0) {
      return divIndex - 1;
    }
    return divIndex;
  }
}
