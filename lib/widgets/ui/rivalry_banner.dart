import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/jars_timezone.dart';
import '../../core/theme.dart';
import '../../models/score.dart';

class RivalryBanner extends StatelessWidget {
  final Score myScore;
  final List<Score> allScores;
  final VoidCallback? onLogTap;

  const RivalryBanner({
    super.key,
    required this.myScore,
    required this.allScores,
    this.onLogTap,
  });

  @override
  Widget build(BuildContext context) {
    final message = _RivalryMessageGenerator(
      myScore: myScore,
      allScores: allScores,
    ).generate();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JarsColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('👀', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: JarsColors.textPrimary,
                  ),
                ),
                if (message.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    message.subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: JarsColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onLogTap != null)
            GestureDetector(
              onTap: onLogTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: JarsColors.primary,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  'Log now',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RivalryMessage {
  final String title;
  final String? subtitle;
  const _RivalryMessage({required this.title, this.subtitle});
}

/// Stable per-user, per-calendar-day RNG so the line doesn't shuffle every frame.
Random _rngForUser(String userId) {
  final d = JarsTimezone.todayChicago();
  final seed = Object.hash(userId, d.year, d.month, d.day);
  return Random(seed);
}

String _name(Score? s) {
  final u = s?.username?.trim();
  if (u == null || u.isEmpty) return 'Someone';
  return u;
}

T _pick<T>(List<T> items, Random r) {
  if (items.isEmpty) {
    throw StateError('empty pick');
  }
  return items[r.nextInt(items.length)];
}

class _RivalryMessageGenerator {
  final Score myScore;
  final List<Score> allScores;

  _RivalryMessageGenerator({
    required this.myScore,
    required this.allScores,
  });

  _RivalryMessage generate() {
    final r = _rngForUser(myScore.userId);

    final sorted = List<Score>.from(allScores)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    if (sorted.isEmpty) {
      return const _RivalryMessage(title: 'No scores yet.', subtitle: null);
    }

    final myIndex = sorted.indexWhere((s) => s.userId == myScore.userId);
    if (myIndex < 0) {
      return const _RivalryMessage(title: 'Score data mismatch.', subtitle: null);
    }

    // ── Solo room ─────────────────────────────────────────────────────────
    if (sorted.length == 1) {
      return _soloRoom(r, myScore);
    }

    final n = sorted.length;
    final othersLogged = allScores.where(
      (s) => s.userId != myScore.userId && s.displayDailyPoints > 0,
    );

    // ── Haven't logged today ────────────────────────────────────────────────
    if (myScore.displayDailyPoints == 0) {
      return _notLoggedToday(r, sorted, myIndex, othersLogged.isNotEmpty);
    }

    // ── Daily leaderboard vs all-time story ────────────────────────────────
    final dailyStory = _dailyVersusTotal(r, sorted, myIndex);
    if (dailyStory != null) return dailyStory;

    final ahead = myIndex > 0 ? sorted[myIndex - 1] : null;
    final behind = myIndex < n - 1 ? sorted[myIndex + 1] : null;
    final gapUp = ahead != null
        ? (ahead.totalScore - myScore.totalScore).toInt()
        : 0;
    final gapDown = behind != null
        ? (myScore.totalScore - behind.totalScore).toInt()
        : 0;

    // ── Photo finish chasing #1 or next rank ───────────────────────────────
    if (ahead != null && gapUp >= 0 && gapUp <= 12) {
      return _photoFinish(
        r: r,
        name: _name(ahead),
        gap: gapUp,
        rank: myIndex + 1,
        totalRanks: n,
      );
    }

    // ── Leading ────────────────────────────────────────────────────────────
    if (myIndex == 0) {
      return _leading(r, sorted, myScore, gapDown);
    }

    // ── Dead last ──────────────────────────────────────────────────────────
    if (myIndex == n - 1) {
      return _lastPlace(r, ahead!, gapUp, n);
    }

    // ── Second overall ─────────────────────────────────────────────────────
    if (myIndex == 1) {
      return _secondPlace(r, ahead!, gapUp, behind, gapDown, n);
    }

    // ── Middle of the pack ─────────────────────────────────────────────────
    return _middlePack(
      r,
      rank: myIndex + 1,
      totalRanks: n,
      ahead: ahead!,
      gapUp: gapUp,
      behind: behind,
      gapDown: gapDown,
    );
  }

  _RivalryMessage _soloRoom(Random r, Score me) {
    final t = me.totalScore.toInt();
    final st = me.streakCurrent;
    return _RivalryMessage(
      title: _pick([
        if (t >= 500)
          'Solo grind: $t pts on the board. Who are you proving it to? You.'
        else if (t >= 100)
          '$t pts and no witnesses. Still counts.'
        else
          'Just you here—every rep is unfiltered.',
        if (st >= 7)
          '$st-day streak. The room is you.'
        else
          'Solo room: the scoreboard is a mirror.',
        'Only name on the list. Make it hurt.',
      ], r),
      subtitle: _pick([
        'Log anyway—future you is watching.',
        'Stack points like nobody can catch you.',
        if (st > 0) 'Streak alive. Keep the chain.',
        null,
      ], r),
    );
  }

  _RivalryMessage _notLoggedToday(
    Random r,
    List<Score> sorted,
    int myIndex,
    bool othersHaveLogged,
  ) {
    if (!othersHaveLogged) {
      return _RivalryMessage(
        title: _pick([
          'No one has punched in today.',
          'The day is still 0–0 for everyone.',
          'Quiet room. First log sets the tone.',
        ], r),
        subtitle: _pick([
          'Be the first to strike.',
          'Own the opening move.',
          'Steal the day before someone else does.',
        ], r),
      );
    }

    final busy = sorted.where((s) => s.displayDailyPoints > 0).length;
    return _RivalryMessage(
      title: _pick([
        "You haven't logged yet—$busy others already did.",
        'Points are moving and your daily is still empty.',
        "The room's rolling. You're still at zero today.",
        'Everyone else is on the board. Clock’s ticking.',
      ], r),
      subtitle: _pick([
        'One set changes the story.',
        'Catch up before the gap gets embarrassing.',
        null,
      ], r),
    );
  }

  /// All-time #1 but someone else is winning *today*, or you're winning today but not overall.
  _RivalryMessage? _dailyVersusTotal(
    Random r,
    List<Score> byTotal,
    int myIndex,
  ) {
    final byDaily = List<Score>.from(allScores)
      ..sort((a, b) => b.displayDailyPoints.compareTo(a.displayDailyPoints));
    if (byDaily.isEmpty) return null;

    final topDaily = byDaily.first;
    if (topDaily.displayDailyPoints <= 0) return null;

    final me = byTotal[myIndex];
    final leaderTotal = byTotal.first;

    // Overall leader but not today's volume king
    if (myIndex == 0 && topDaily.userId != me.userId) {
      final dn = _name(topDaily);
      final theirDaily = topDaily.displayDailyPoints.toInt();
      return _RivalryMessage(
        title: _pick([
          "#1 overall, but $dn's stacking $theirDaily pts today.",
          'Top of the board—yet $dn owns the day so far.',
          "$dn's feeding the daily. You're still the war, they're winning the battle.",
        ], r),
        subtitle: _pick([
          'Match the energy or they close the gap.',
          'Drop a log and steal the narrative.',
          null,
        ], r),
      );
    }

    // Not #1 overall but leading today
    if (myIndex != 0 && topDaily.userId == me.userId) {
      final gap = (leaderTotal.totalScore - me.totalScore).toInt();
      return _RivalryMessage(
        title: _pick([
          "Today's yours—${_name(leaderTotal)} is still $gap pts up overall.",
          'Carrying the daily. Total score still has homework.',
          "Leading today. The crown's still ${_name(leaderTotal)}'s.",
        ], r),
        subtitle: _pick([
          'Keep today loud; chip at the gap.',
          'Translate this energy into the big number.',
          null,
        ], r),
      );
    }

    return null;
  }

  _RivalryMessage _photoFinish({
    required Random r,
    required String name,
    required int gap,
    required int rank,
    required int totalRanks,
  }) {
    final g = gap.clamp(0, 999);
    return _RivalryMessage(
      title: _pick([
        if (g == 0)
          '$name and you are tied—tiebreakers are earned, not given.'
        else if (g <= 3)
          '$g pt${g == 1 ? '' : 's'}—one good log flips this.'
        else
          'Only $g pts to $name. Photo finish energy.',
        '$name by $g. Sleep on that if you dare.',
        if (rank == 2)
          'Second place, $g pts back. Annoyingly close.'
        else
          '$g pts off $name. Annoyingly close.',
      ], r),
      subtitle: _pick([
        if (totalRanks > 2) '$totalRanks deep—edges matter.',
        'No room for soft sets.',
        null,
      ], r),
    );
  }

  _RivalryMessage _leading(
    Random r,
    List<Score> sorted,
    Score me,
    int gapToSecond,
  ) {
    if (sorted.length < 2) {
      return _RivalryMessage(
        title: _pick([
          "You're in first place.",
          'Top of the stack.',
        ], r),
        subtitle: _pick(['Keep pushing.', 'Hold the line.', null], r),
      );
    }

    final second = sorted[1];
    final sn = _name(second);
    final g = gapToSecond;

    if (g <= 5) {
      return _RivalryMessage(
        title: _pick([
          "Leading by $g—$sn is breathing on your neck.",
          '$sn within $g pts. Crown’s rented.',
          "First, but $sn's a bad dream away.",
        ], r),
        subtitle: _pick(['Log before they do.', 'Extend or regret.', null], r),
      );
    }
    if (g <= 25) {
      return _RivalryMessage(
        title: _pick([
          "You're up $g on $sn—not safe yet.",
          '$g-pt cushion over $sn. Workable, not comfy.',
          "$sn trails by $g. Don't get cute.",
        ], r),
        subtitle: _pick(['Pad it.', 'Stay greedy.', null], r),
      );
    }
    if (g <= 80) {
      return _RivalryMessage(
        title: _pick([
          "$sn's $g pts back—solid lead, still a race.",
          'Up $g on $sn. Room for swagger, not sleep.',
        ], r),
        subtitle: _pick(['Keep pouring it on.', null], r),
      );
    }
    return _RivalryMessage(
      title: _pick([
        "You're running away—$sn is $g pts behind.",
        '$g-pt gap on $sn. Borderline rude.',
        "$sn down $g. That's a statement.",
      ], r),
      subtitle: _pick([
        'Don’t let the room forget who’s #1.',
        null,
      ], r),
    );
  }

  _RivalryMessage _lastPlace(
    Random r,
    Score personAbove,
    int gapUp,
    int totalRanks,
  ) {
    final n = _name(personAbove);
    return _RivalryMessage(
      title: _pick([
        'Last on the board—only one direction left.',
        '$n is $gapUp pts ahead. Basement has an exit.',
        '$totalRanks fighters and you’re holding the rear.',
        "Someone's gotta be last—prove it's temporary.",
      ], r),
      subtitle: _pick([
        if (gapUp <= 25) 'Small gap. One session changes the story.'
        else
          'Chip away—marathon, not sprint.',
        'Log ugly if you have to—just log.',
        null,
      ], r),
    );
  }

  _RivalryMessage _secondPlace(
    Random r,
    Score leader,
    int gapUp,
    Score? third,
    int gapToThird,
    int totalRanks,
  ) {
    final ln = _name(leader);
    if (third != null && gapToThird <= 15) {
      return _RivalryMessage(
        title: _pick([
          '$ln ahead, ${_name(third)} behind—sandwich season.',
          'Caught between $ln and ${_name(third)}. Choose violence.',
        ], r),
        subtitle: _pick(['Pick a direction and commit.', null], r),
      );
    }
    return _RivalryMessage(
      title: _pick([
        'Silver: $ln leads by $gapUp pts.',
        '$gapUp pts off $ln—second hurts if you stay polite.',
        "Second place. $ln's the name on the door.",
      ], r),
      subtitle: _pick([
        if (totalRanks > 2) '$totalRanks deep—plenty of room to climb or slip.'
        else
          'Head-to-head for the top.',
        null,
      ], r),
    );
  }

  _RivalryMessage _middlePack(
    Random r, {
    required int rank,
    required int totalRanks,
    required Score ahead,
    required int gapUp,
    required Score? behind,
    required int gapDown,
  }) {
    final an = _name(ahead);
    if (behind != null && gapDown <= 8) {
      return _RivalryMessage(
        title: _pick([
          '${_name(behind)} is $gapDown pts back—watch your six.',
          'Pressure from below: ${_name(behind)} within $gapDown.',
        ], r),
        subtitle: _pick(['Climb before you get passed.', null], r),
      );
    }
    return _RivalryMessage(
      title: _pick([
        '#$rank of $totalRanks—$an is $gapUp pts up.',
        '$gapUp to pass $an. The meat of the ladder.',
        'Middle war: chase $an, don’t gift ${_name(behind)} behind you.',
      ], r),
      subtitle: _pick([
        'Two-front fight: up and down.',
        null,
      ], r),
    );
  }
}
