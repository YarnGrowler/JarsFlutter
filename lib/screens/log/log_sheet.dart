import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/count_unit.dart';
import '../../core/rank_bonus.dart';
import '../../core/streak_bonus.dart';
import '../../core/level_data.dart';
import '../../core/log_screen_style.dart';
import '../../core/theme.dart';
import '../../models/exercise.dart';
import '../../models/score.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/exercise_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/score_provider.dart';
import '../../services/ai_events_service.dart';
import '../../services/event_service.dart';
import '../../services/log_service.dart';
import '../../services/notification_service.dart';
import '../../services/score_service.dart' show ScoreService, previewStreakDaysForBonus;
import '../../services/supabase_service.dart';
import '../../widgets/ui/rank_badge.dart';
import 'rank_up_ceremony_screen.dart';
import 'widgets/animated_points_display.dart';
import 'widgets/log_exercise_card.dart';
import 'widgets/radial_rep_picker.dart';
import 'widgets/weight_picker_panel.dart' show showWeightPicker;

// ─────────────────────────────────────────────────────────────────────────────
const Duration _kHoldDuration = Duration(seconds: 2);
const Duration _kTapMax = Duration(milliseconds: 300);
const double _kSwipeUpThreshold = 18.0; // px upward before opening picker

/// Hold-progress ring: small canvas + repaint boundary so web/mobile don’t
/// repaint a full-screen layer every tick; size ≥ 2× ring radius + stroke.
const double _kHoldRingCanvasSize = 200.0;
/// Nudge ring center down so it wraps the Space Mono rep (glyph sits low).
const double _kHoldRingCenterYOffset = 48.0;

const String _kRecentExercisesKey = 'jars_recent_exercises';
const String _kWeightKeyPrefix = 'jars_weight_';
const int _kMaxRecents = 10;
const String _kRecentsCategory = 'Recents';
const String _kDefaultCategory = 'Upper Body';

/// Bottom exercise sheet: snapped between min (default peek) and max 75% screen.
const double _kLogSheetMin = 0.36;
const double _kLogSheetMax = 0.75;

class LogSheet extends ConsumerStatefulWidget {
  const LogSheet({super.key});

  @override
  ConsumerState<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<LogSheet>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _selectedCategory;
  Exercise? _selectedExercise;
  int _reps = 0;
  double _weight = 0;

  /// Plank-style stopwatch (ms accumulated + optional running [Stopwatch]).
  int _timerAccumMs = 0;
  Stopwatch? _timerSw;
  Timer? _timerUiTick;

  /// Post-submit streak bonus animation (null = normal points preview).
  int? _celebrationBase;
  int? _celebrationStreakBonus;
  int? _celebrationRankBonus;
  int? _celebrationTotal;
  int? _celebrationStreakDays;
  int? _celebrationRank; // 1/2/3 (null = no rank bonus shown)

  // recents / search
  List<String> _recentIds = [];
  final _searchController = TextEditingController();
  String _searchQuery = '';

  final _numberKey = GlobalKey();
  final _random = math.Random();
  late AnimationController _repBump;
  double _repBumpTurn = 0;
  bool _powerRepBump = false;

  // weight picker
  bool _weightPanelOpen = false;

  // hold-to-log state
  AnimationController? _holdCtrl;
  bool _holding = false;
  bool _sustainingFlood = false;
  Offset? _sustainOrigin;
  bool _logging = false;
  Offset? _holdOrigin;

  // pointer tracking (for distinguishing tap vs hold vs swipe)
  Offset? _pointerStart;
  DateTime? _pointerDownAt;
  bool _movedEnoughForSwipe = false;
  bool _pickerOpen = false;

  // undo
  String? _undoLogId;
  double _undoPoints = 0;

  double _sheetExtent = _kLogSheetMin;
  final DraggableScrollableController _sheetCtrl = DraggableScrollableController();

  bool get _timerUiActive {
    final e = _selectedExercise;
    return e != null && e.effectiveTimerUi;
  }

  int get _timerMsTotal =>
      _timerAccumMs + (_timerSw?.elapsedMilliseconds ?? 0);

  void _resetTimerState() {
    _timerUiTick?.cancel();
    _timerUiTick = null;
    _timerSw?.stop();
    _timerSw = null;
    _timerAccumMs = 0;
  }

  /// Web / PWA: pause when the tab or app goes to background so time isn’t counted while away.
  void _pauseTimerClock() {
    if (_timerSw != null) {
      _timerAccumMs += _timerSw!.elapsedMilliseconds;
      _timerSw!.stop();
      _timerSw = null;
    }
    _timerUiTick?.cancel();
    _timerUiTick = null;
    if (mounted) {
      setState(() {
        _reps = (_timerMsTotal / 1000).floor();
      });
    }
  }

  void _toggleTimer() {
    if (_logging || _celebrationTotal != null) return;
    if (_timerSw?.isRunning ?? false) {
      _pauseTimerClock();
      return;
    }
    _timerSw = Stopwatch()..start();
    _timerUiTick?.cancel();
    _timerUiTick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      setState(() {
        _reps = (_timerMsTotal / 1000).floor();
      });
    });
    HapticFeedback.selectionClick();
  }

  /// Under 1 min: compact `5.2s` (no leading minute digits). At 1+ min: `1:05.2`.
  String _formatTimerMs(int ms) {
    var t = ms;
    if (t < 0) t = 0;
    if (t < 60000) {
      final sec = t / 1000.0;
      return '${sec.toStringAsFixed(1)}s';
    }
    final m = t ~/ 60000;
    final rem = t % 60000;
    final s = rem ~/ 1000;
    final tenths = ((rem % 1000) / 100).floor().clamp(0, 9);
    return '$m:${s.toString().padLeft(2, '0')}.$tenths';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repBump = AnimationController(vsync: this, duration: kRepBumpTotal)
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _repBump.reset();
      });
    _loadRecents();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerUiTick?.cancel();
    _timerSw?.stop();
    _sheetCtrl.dispose();
    _holdCtrl?.dispose();
    _repBump.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_timerUiActive) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pauseTimerClock();
    }
  }

  // ── SharedPreferences ─────────────────────────────────────────────────────
  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_kRecentExercisesKey) ?? [];
    if (mounted) {
      setState(() {
        _recentIds = ids;
        if (ids.isNotEmpty && _selectedCategory == null) {
          _selectedCategory = _kRecentsCategory;
        }
      });
    }
  }

  Future<void> _saveRecent(Exercise ex) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = List<String>.from(_recentIds);
    ids.remove(ex.id);
    ids.insert(0, ex.id);
    if (ids.length > _kMaxRecents) ids.removeRange(_kMaxRecents, ids.length);
    await prefs.setStringList(_kRecentExercisesKey, ids);
    if (mounted) setState(() => _recentIds = ids);
  }

  Future<double> _loadWeight(String exerciseId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('$_kWeightKeyPrefix$exerciseId') ?? 0.0;
  }

  Future<void> _saveWeight(String exerciseId, double weight) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('$_kWeightKeyPrefix$exerciseId', weight);
  }

  // ── Rep bump (~80% original shake, ~20% bigger scale/tilt + longer) ────────
  Duration get _repBumpDuration =>
      _powerRepBump ? kRepBumpPower : kRepBumpTotal;

  double _bumpPeak() => _powerRepBump ? 0.28 : 0.18;

  double _bumpScale() {
    final t = _repBump.value;
    final peak = _bumpPeak();
    if (t < 60 / 180) return 1 + peak * (t / (60 / 180));
    final t2 = (t - 60 / 180) / (120 / 180);
    return 1 + peak - peak * Curves.easeOut.transform(t2.clamp(0.0, 1.0));
  }

  double _bumpTurn() {
    final t = _repBump.value;
    if (t < 60 / 180) {
      return _repBumpTurn * (t / (60 / 180)).clamp(0.0, 1.0);
    }
    final t2 = (t - 60 / 180) / (120 / 180);
    return _repBumpTurn *
        (1 - Curves.easeOut.transform(t2.clamp(0.0, 1.0)));
  }

  void _incrementRep() {
    if (_logging || _celebrationTotal != null) return;
    if (_selectedExercise == null) return;
    if (_selectedExercise!.effectiveTimerUi) {
      return;
    }
    final power = _random.nextDouble() < 0.2;
    if (power) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    final deg = power ? 6.0 : 2.0;
    setState(() {
      _reps++;
      _powerRepBump = power;
      _repBumpTurn =
          (_random.nextBool() ? 1 : -1) * deg * math.pi / 180;
    });
    _repBump.duration = _repBumpDuration;
    _repBump.forward(from: 0);
  }

  // ── Hold-to-log ────────────────────────────────────────────────────────────
  void _startHold(Offset globalPos) {
    if (_selectedExercise == null ||
        _logging ||
        _celebrationTotal != null ||
        _pickerOpen ||
        _weightPanelOpen) {
      return;
    }
    if (_timerUiActive) {
      if (_timerMsTotal < 1000) return;
    } else if (_reps < 1) {
      return;
    }
    _cancelHold();
    _holdOrigin = globalPos;

    _holdCtrl = AnimationController(vsync: this, duration: _kHoldDuration)
      ..addListener(() => setState(() {}))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          _onHoldComplete();
        }
      });

    // Delay flood start slightly — only start visually after user holds ≥ 200ms
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || _holdCtrl == null) return;
      setState(() => _holding = true);
      _holdCtrl!.forward();
    });

    // Haptics at 1s mark
    int hapticTick = 0;
    _holdCtrl!.addListener(() {
      final tick = (_holdCtrl!.value * 2).floor().clamp(0, 1);
      if (tick > hapticTick) {
        hapticTick = tick;
        HapticFeedback.selectionClick();
      }
    });
  }

  void _cancelHold() {
    _holdCtrl?.stop();
    _holdCtrl?.dispose();
    _holdCtrl = null;
    _holdOrigin = null;
    if (_holding || _sustainingFlood) {
      setState(() {
        _holding = false;
        _sustainingFlood = false;
        _sustainOrigin = null;
      });
    }
  }

  Future<void> _onHoldComplete() async {
    if (!mounted || _logging) return;
    final origin = _holdOrigin;
    _holdCtrl?.dispose();
    _holdCtrl = null;

    setState(() {
      _holding = false;
      _holdOrigin = null;
      _sustainingFlood = true;
      _sustainOrigin = origin;
    });

    // Flood stays full for 1s
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    // Flash fires while flood still showing
    HapticFeedback.heavyImpact();
    await _flashWhite();
    if (!mounted) return;

    setState(() {
      _sustainingFlood = false;
      _sustainOrigin = null;
    });

    await _submitLog(alreadyFlashed: true);
  }

  // ── Pointer events ─────────────────────────────────────────────────────────
  //
  // Interaction logic:
  //   - Tap anywhere in top zone → increment rep
  //   - Swipe UP in rep + points area → open rep picker
  //   - Long press (hold ≥ 2s) anywhere → flood + confirm
  //   - Swipe sideways on number while holding → cancel hold
  //
  void _onPointerDown(PointerDownEvent e) {
    if (_selectedExercise == null) return;
    if (_logging || _celebrationTotal != null) return;
    _pointerStart = e.position;
    _pointerDownAt = DateTime.now();
    _movedEnoughForSwipe = false;

    // Start hold timer immediately — will be cancelled if it's a quick tap
    _startHold(e.position);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_pointerStart == null) return;
    final delta = e.position - _pointerStart!;
    final dist = delta.distance;

    // Swipe UP anywhere in the rep + points listener zone → open rep picker
    if (!_movedEnoughForSwipe &&
        dist > _kSwipeUpThreshold &&
        delta.dy < 0 &&
        delta.dy.abs() > delta.dx.abs()) {
      _movedEnoughForSwipe = true;
      _cancelHold();
      _openRepPicker();
      return;
    }

    // Cancel hold if user moves too much in any direction
    if (_holding && dist > 30) {
      _cancelHold();
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final downAt = _pointerDownAt;
    _pointerDownAt = null;

    final elapsed = downAt != null
        ? DateTime.now().difference(downAt)
        : Duration.zero;

    final didSwipe = _movedEnoughForSwipe;
    _movedEnoughForSwipe = false;

    // Quick tap: timer exercises toggle stopwatch; others increment count.
    if (!didSwipe && !_pickerOpen && elapsed < _kTapMax) {
      _cancelHold();
      if (_timerUiActive) {
        _toggleTimer();
      } else {
        _incrementRep();
      }
    } else if (!didSwipe) {
      // Long press ended before completion → cancel
      _cancelHold();
    }

    _pointerStart = null;
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointerDownAt = null;
    _pointerStart = null;
    _movedEnoughForSwipe = false;
    _cancelHold();
  }

  void _openRepPicker() {
    if (_logging || _celebrationTotal != null) return;
    if (_pickerOpen) return;
    if (_timerUiActive) _pauseTimerClock();
    _pickerOpen = true;
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (_timerUiActive) {
          final totalSec =
              (_timerMsTotal / 1000).floor().clamp(0, MinSecWheelPicker.maxTotalSeconds);
          return SafeArea(
            child: MinSecWheelPicker(
              initialTotalSeconds: totalSec,
              onTotalSecondsChanged: (sec) {
                if (!mounted) return;
                setState(() {
                  _reps = sec;
                  _timerAccumMs = sec * 1000;
                  _timerSw?.stop();
                  _timerSw = null;
                });
              },
            ),
          );
        }
        return SafeArea(
          child: RadialRepPicker(
            initialValue: _reps,
            countUnit: _selectedExercise?.countUnit ?? CountUnit.reps,
            onRepsChanged: (v) {
              if (!mounted) return;
              setState(() => _reps = v);
            },
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _pickerOpen = false);
    });
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  Future<void> _submitLog({bool alreadyFlashed = false}) async {
    if (_logging) return;
    final exercise = _selectedExercise;
    final room = ref.read(activeRoomProvider);
    if (exercise == null || room == null) return;

    var count = _reps;
    if (exercise.effectiveTimerUi) {
      _pauseTimerClock();
      count = (_timerMsTotal / 1000).floor();
    }
    if (count < 1) return;

    final userId = SupabaseService.currentUserId!;
    final basePts =
        exercise.calculatePoints(count, _weight > 0 ? _weight : null);
    setState(() => _logging = true);

    if (_weight > 0) await _saveWeight(exercise.id, _weight);

    try {
      final before = await ScoreService.getUserScore(room.id, userId);
      final totalBefore = before?.totalScore ?? 0;
      final oldLevel = getLevelForScore(totalBefore);

      final streakDays = before == null
          ? 0
          : previewStreakDaysForBonus(
              score: before,
              basePoints: basePts,
              streakMinimum: room.streakMinimum,
            );
      final streakBonusPts = streakBonusPointsRounded(
        basePoints: basePts,
        streakDaysForBonus: streakDays,
      );
      final baseRounded = basePts.round();

      // Rank bonus: based on *current* all-time rank before this log.
      // Only ranks 1–3 get a small percentage boost, applied on top of streak bonus.
      int? myRank;
      try {
        final scores = await ScoreService.getRoomScores(room.id);
        scores.sort((a, b) {
          final byScore = b.totalScore.compareTo(a.totalScore);
          if (byScore != 0) return byScore;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        final idx = scores.indexWhere((s) => s.userId == userId);
        if (idx >= 0) myRank = idx + 1;
      } catch (_) {
        // If rank fetch fails, we still allow logging without the bonus.
      }

      final subtotalPts = baseRounded + streakBonusPts;
      final rankBonusPts = myRank == null
          ? 0
          : rankBonusPointsRounded(pointsSoFar: subtotalPts, rank: myRank!);

      final totalPts = subtotalPts + rankBonusPts;
      final totalEarned = totalPts.toDouble();

      final log = await LogService.insertLog(
        roomId: room.id,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        count: count,
        weight: _weight,
        pointsEarned: totalEarned,
        countUnit: exercise.countUnit,
      );

      unawaited(
        LogService.ensureIdleWakeCards(room.id, actorUserId: userId),
      );

      await ScoreService.addPoints(
        roomId: room.id,
        points: totalEarned,
        streakMinimum: room.streakMinimum,
      );

      // Invoked AFTER addPoints so the Edge function reads fresh scores.
      unawaited(AiEventsService.processAfterLog(log.id));
      ref.invalidate(myScoreProvider);
      ref.invalidate(roomScoresProvider);
      ref.invalidate(groupGoalProgressProvider);

      final after = await ScoreService.getUserScore(room.id, userId);
      final totalAfter = after?.totalScore ?? totalBefore + totalEarned;
      final newLevel = getLevelForScore(totalAfter);
      final username = after?.username ?? before?.username ?? 'You';

      unawaited(EventService.checkAndBroadcast(
        roomId: room.id,
        userId: userId,
        username: username,
        exerciseName: exercise.name,
        repCount: count,
        logWeight: _weight,
        pointsBefore: totalBefore,
        pointsAfter: totalAfter,
        streakBefore: before?.streakCurrent ?? 0,
        streakAfter: after?.streakCurrent ?? 0,
        currentLogId: log.id,
      ));

      if (mounted) {
        setState(() {
          if (streakBonusPts > 0 || rankBonusPts > 0) {
            _celebrationBase = baseRounded;
            _celebrationStreakBonus = streakBonusPts;
            _celebrationRankBonus = rankBonusPts;
            _celebrationTotal = totalPts;
            _celebrationStreakDays = streakDays > 0 ? streakDays : 1;
            _celebrationRank = (myRank != null && myRank! <= 3) ? myRank : null;
          }
        });
        final waitMs = (streakBonusPts > 0 ? 2000 : 350) +
            (rankBonusPts > 0 ? 700 : 0);
        await Future<void>.delayed(Duration(milliseconds: waitMs));
      }
      if (!mounted) return;

      if (newLevel.level > oldLevel.level) {
        await LogService.insertRankUpBroadcast(
            roomId: room.id, rankTitle: newLevel.title);
        unawaited(
          NotificationService.notifyRoomMembersExcept(
            roomId: room.id,
            excludeUserId: userId,
            body: '$username leveled up to ${newLevel.title}!',
          ),
        );
        if (mounted) {
          await Navigator.of(context, rootNavigator: true).push(
            PageRouteBuilder<void>(
              opaque: true,
              pageBuilder: (_, __, ___) => RankUpCeremonyScreen(
                previousLevel: oldLevel,
                newLevel: newLevel,
                username: username,
                totalPoints: totalAfter,
                previousThreshold: oldLevel.threshold,
              ),
            ),
          );
        }
      }

      if (mounted) {
        _resetTimerState();
        setState(() {
          _undoLogId = log.id;
          _undoPoints = totalEarned;
          _reps = 0;
          _weight = 0;
          _logging = false;
          _celebrationBase = null;
          _celebrationStreakBonus = null;
          _celebrationRankBonus = null;
          _celebrationTotal = null;
          _celebrationStreakDays = null;
          _celebrationRank = null;
        });
        if (!alreadyFlashed) await _flashWhite();
        if (mounted) context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _logging = false);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _flashWhite() async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => const IgnorePointer(
        child: ColoredBox(color: Color(0xF0FFFFFF), child: SizedBox.expand()),
      ),
    );
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    entry.remove();
  }

  Future<void> _undoLog() async {
    final id = _undoLogId;
    if (id == null) return;
    final room = ref.read(activeRoomProvider);
    if (room == null) return;
    try {
      await LogService.deleteLog(id);
      await ScoreService.subtractPoints(roomId: room.id, points: _undoPoints);
      ref.invalidate(myScoreProvider);
      ref.invalidate(roomScoresProvider);
      ref.invalidate(groupGoalProgressProvider);
      if (mounted) setState(() => _undoLogId = null);
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final room = ref.watch(activeRoomProvider);
    final exercisesAsync = ref.watch(roomExercisesProvider);
    final scoreAsync = ref.watch(myScoreProvider);

    if (room == null) {
      return Scaffold(
        backgroundColor: kLogNearBlack,
        body: Center(
            child: Text('Join a room first',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, color: JarsColors.textSecondary))),
      );
    }

    final exercise = _selectedExercise;
    final countUnit = exercise?.countUnit ?? CountUnit.reps;
    final countUnitPlural = countUnit.pickerHint;
    final swipePickerHint = exercise != null && exercise.effectiveTimerUi
        ? 'minutes & seconds'
        : countUnitPlural;
    String tapCountHint() {
      if (exercise != null && exercise.effectiveTimerUi) {
        return 'tap to start/pause · swipe up for min:sec · hold 2s to log';
      }
      switch (countUnit) {
        case CountUnit.reps:
          return 'tap to count · hold 2s to log';
        case CountUnit.seconds:
          return 'tap to add seconds · hold 2s to log';
        case CountUnit.minutes:
          return 'tap to add minutes · hold 2s to log';
      }
    }

    final previewCount =
        exercise != null && exercise.effectiveTimerUi
            ? (_timerMsTotal / 1000).floor()
            : _reps;
    final ptsPreview = exercise == null
        ? 0.0
        : exercise.calculatePoints(
            previewCount.clamp(0, 999999),
            _weight > 0 ? _weight : null,
          );
    final holdProgress = _holdCtrl?.value ?? 0.0;
    final showFlood = (_holding && holdProgress > 0) || _sustainingFlood;
    final floodProgress = _sustainingFlood ? 1.0 : holdProgress;
    final floodOrigin = _sustainingFlood ? _sustainOrigin : _holdOrigin;
    final secondsLeft = _holding
        ? (_kHoldDuration.inSeconds * (1 - holdProgress)).ceil()
        : 0;

    final h = MediaQuery.sizeOf(context).height;
    final padBottom = MediaQuery.of(context).padding.bottom;
    final sheetPadBottom = h * _sheetExtent;
    // Reserve space for the sheet's *peek* height only. Using [_sheetExtent] here
    // would resize this column while dragging ("pushing" the UI). The sheet still
    // paints on top when expanded past the peek.
    final sheetPeekReserve = h * _kLogSheetMin;

    return Scaffold(
      backgroundColor: kLogNearBlack,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SafeArea(
                bottom: false,
                child: _TopBar(
                  scoreAsync: scoreAsync,
                  onHistoryTap: () => context.push('/log-history'),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: sheetPeekReserve),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Listener(
                                  behavior: HitTestBehavior.translucent,
                                  onPointerDown: _onPointerDown,
                                  onPointerMove: _onPointerMove,
                                  onPointerUp: _onPointerUp,
                                  onPointerCancel: _onPointerCancel,
                                  child: SizedBox.expand(
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        if (_holding && holdProgress > 0)
                                          Positioned.fill(
                                            child: IgnorePointer(
                                              child: Center(
                                                child: RepaintBoundary(
                                                  child: SizedBox(
                                                    width: _kHoldRingCanvasSize,
                                                    height: _kHoldRingCanvasSize,
                                                    child: _HoldRing(
                                                      progress: holdProgress,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_holding && holdProgress > 0.05)
                                          Positioned(
                                            bottom: 20,
                                            left: 0,
                                            right: 0,
                                            child: IgnorePointer(
                                              child: Center(
                                                child: Text(
                                                  secondsLeft > 0
                                                      ? 'hold $secondsLeft more…'
                                                      : 'releasing…',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.75),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_selectedExercise != null &&
                                            (previewCount > 0 ||
                                                (_timerUiActive &&
                                                    _timerMsTotal > 0)) &&
                                            !_holding)
                                          Positioned(
                                            top: 12,
                                            left: 0,
                                            right: 0,
                                            child: IgnorePointer(
                                              child: Center(
                                                child: Text(
                                                  '↑ swipe up here (or on points) to set $swipePickerHint',
                                                  textAlign: TextAlign.center,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.18),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_selectedExercise == null)
                                          Positioned(
                                            bottom: 16,
                                            left: 0,
                                            right: 0,
                                            child: IgnorePointer(
                                              child: Center(
                                                child: Text(
                                                  'Pick an exercise in the sheet below',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.22),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (_selectedExercise != null &&
                                            previewCount == 0 &&
                                            (!_timerUiActive ||
                                                _timerMsTotal == 0))
                                          Positioned(
                                            bottom: 16,
                                            left: 0,
                                            right: 0,
                                            child: IgnorePointer(
                                              child: Center(
                                                child: Text(
                                                  tapCountHint(),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.22),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (exercise != null && exercise.supportsWeight)
                                  Positioned(
                                    right: 16,
                                    bottom: 12,
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: InkWell(
                                        onTap: () {
                                          setState(
                                              () => _weightPanelOpen = true);
                                          showWeightPicker(
                                            context: context,
                                            initial: _weight,
                                            onConfirm: (w) {
                                              if (mounted) {
                                                setState(() => _weight = w);
                                              }
                                            },
                                          ).whenComplete(() {
                                            if (mounted) {
                                              setState(() =>
                                                  _weightPanelOpen = false);
                                            }
                                          });
                                        },
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        child: _WeightBadge(weight: _weight),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: h * 0.12,
                            child: Center(
                              child: AnimatedPointsDisplay(
                                key: ValueKey(
                                  '${exercise?.id ?? 'none'}_${_celebrationTotal ?? 0}',
                                ),
                                targetPoints: ptsPreview,
                                visible: exercise != null,
                                celebrationBase: _celebrationBase,
                                celebrationStreakBonus: _celebrationStreakBonus,
                                celebrationRankBonus: _celebrationRankBonus,
                                celebrationTotal: _celebrationTotal,
                                celebrationStreakDays: _celebrationStreakDays,
                                celebrationRank: _celebrationRank,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (showFlood && floodOrigin != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _FloodOverlay(
                              progress: floodProgress,
                              originGlobal: floodOrigin,
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Center(
                            child: Transform.scale(
                              scale: _bumpScale(),
                              child: Transform.rotate(
                                angle: _bumpTurn(),
                                child: Text(
                                  _timerUiActive
                                      ? _formatTimerMs(_timerMsTotal)
                                      : '$_reps',
                                  key: _numberKey,
                                  style: GoogleFonts.spaceMono(
                                    fontSize: _timerUiActive ? 72 : 96,
                                    fontWeight: FontWeight.w700,
                                    color: (_holding || _sustainingFlood)
                                        ? Colors.white
                                        : (_selectedExercise != null
                                            ? kLogText
                                            : kLogText.withValues(
                                                alpha: 0.22)),
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              if (mounted && (n.extent - _sheetExtent).abs() > 0.001) {
                setState(() => _sheetExtent = n.extent);
              }
              return false;
            },
            child: DraggableScrollableSheet(
              controller: _sheetCtrl,
              initialChildSize: _kLogSheetMin,
              minChildSize: _kLogSheetMin,
              maxChildSize: _kLogSheetMax,
              snap: true,
              snapSizes: const [_kLogSheetMin, _kLogSheetMax],
              builder: (ctx, scrollController) {
                final screenH = MediaQuery.sizeOf(ctx).height;
                Widget fixedHeader({required Widget categoryPills}) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SheetDragHandle(
                          controller: _sheetCtrl,
                          screenHeight: screenH,
                        ),
                        _SearchBar(
                          controller: _searchController,
                          onClear: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        categoryPills,
                      ],
                    ),
                  );
                }

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: kLogSurface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: exercisesAsync.when(
                      loading: () => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          fixedHeader(
                            categoryPills: const SizedBox(height: 40),
                          ),
                          Expanded(
                            child: CustomScrollView(
                              controller: scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: const [
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: kLogPurple,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      error: (e, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          fixedHeader(categoryPills: const SizedBox.shrink()),
                          Expanded(
                            child: CustomScrollView(
                              controller: scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Text(
                                      'Error: $e',
                                      style: GoogleFonts.inter(
                                          color: Colors.white54),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      data: (exercises) {
                        final filtered = _filterExercises(exercises);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            fixedHeader(
                              categoryPills: _searchQuery.isEmpty
                                  ? _CategoryPills(
                                      exercises: exercises,
                                      recentIds: _recentIds,
                                      selected: _selectedCategory ??
                                          (_recentIds.isNotEmpty
                                              ? _kRecentsCategory
                                              : _kDefaultCategory),
                                      onSelect: (c) =>
                                          setState(() => _selectedCategory = c),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            Expanded(
                              child: CustomScrollView(
                                controller: scrollController,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                ),
                                slivers: [
                                  if (filtered.isEmpty)
                                    SliverFillRemaining(
                                      child: Center(
                                        child: Text(
                                          _searchQuery.isNotEmpty
                                              ? 'No results for "$_searchQuery"'
                                              : 'No exercises yet',
                                          style: GoogleFonts.inter(
                                            color: Colors.white38,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 6, 14, 24),
                                      sliver: SliverGrid(
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                          mainAxisExtent: 80,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, i) {
                                            final ex = filtered[i];
                                            return LogExerciseCard(
                                              exercise: ex,
                                              selected: exercise?.id == ex.id,
                                              onTap: () async {
                                                final saved =
                                                    await _loadWeight(ex.id);
                                                if (!mounted) return;
                                                _resetTimerState();
                                                setState(() {
                                                  _selectedExercise = ex;
                                                  _reps = 0;
                                                  _weight = saved;
                                                  if (_searchQuery.isNotEmpty) {
                                                    _searchController.clear();
                                                    _searchQuery = '';
                                                  }
                                                });
                                                await _saveRecent(ex);
                                              },
                                            );
                                          },
                                          childCount: filtered.length,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),

          if (_undoLogId != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: padBottom + sheetPadBottom + 8,
              child: _UndoBar(onUndo: _undoLog),
            ),
        ],
      ),
    );
  }

  List<Exercise> _filterExercises(List<Exercise> exercises) {
    if (_searchQuery.isNotEmpty) {
      return exercises
          .where((e) => e.name.toLowerCase().contains(_searchQuery))
          .toList();
    }

    final cats = exercises.map((e) => e.category).toSet().toList()..sort();
    final defaultCat = _recentIds.isNotEmpty
        ? _kRecentsCategory
        : (cats.contains(_kDefaultCategory)
            ? _kDefaultCategory
            : (cats.isNotEmpty ? cats.first : null));
    final activeCat = _selectedCategory ?? defaultCat;

    if (activeCat == _kRecentsCategory) {
      return _recentIds
          .map((id) {
            try {
              return exercises.firstWhere((e) => e.id == id);
            } catch (_) {
              return null;
            }
          })
          .whereType<Exercise>()
          .toList();
    }

    return activeCat == null
        ? exercises
        : exercises.where((e) => e.category == activeCat).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet chrome
// ─────────────────────────────────────────────────────────────────────────────

class _SheetDragHandle extends StatelessWidget {
  final DraggableScrollableController controller;
  final double screenHeight;

  const _SheetDragHandle({
    required this.controller,
    required this.screenHeight,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        if (!controller.isAttached) return;
        final dy = details.primaryDelta ?? 0;
        final next = (controller.size - dy / screenHeight)
            .clamp(_kLogSheetMin, _kLogSheetMax);
        controller.jumpTo(next);
      },
      onVerticalDragEnd: (_) {
        if (!controller.isAttached) return;
        final s = controller.size;
        final mid = (_kLogSheetMin + _kLogSheetMax) / 2;
        final target = s < mid ? _kLogSheetMin : _kLogSheetMax;
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Center(
          child: Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search bar
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onClear;

  const _SearchBar({required this.controller, required this.onClear});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return TextField(
      controller: widget.controller,
      style: GoogleFonts.inter(fontSize: 14, color: Colors.white),
      cursorColor: kLogPurple,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search',
        hintStyle: GoogleFonts.inter(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.32),
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Icon(
            Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.35),
            size: 22,
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 40, minHeight: 44),
        suffixIcon: hasText
            ? IconButton(
                onPressed: widget.onClear,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.09),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(
            color: kLogPurple.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Purple flood overlay
// ─────────────────────────────────────────────────────────────────────────────

class _FloodOverlay extends StatelessWidget {
  final double progress;
  final Offset originGlobal;

  const _FloodOverlay({required this.progress, required this.originGlobal});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final box = ctx.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.globalToLocal(originGlobal)
          : Offset(c.maxWidth / 2, c.maxHeight / 2);

      double maxR = 0;
      for (final corner in [
        Offset.zero,
        Offset(c.maxWidth, 0),
        Offset(0, c.maxHeight),
        Offset(c.maxWidth, c.maxHeight),
      ]) {
        final d = (corner - origin).distance;
        if (d > maxR) maxR = d;
      }

      final eased = Curves.easeInCubic.transform(progress);
      final radius = maxR * eased;

      return CustomPaint(
        size: Size(c.maxWidth, c.maxHeight),
        painter: _FloodPainter(origin: origin, radius: radius),
      );
    });
  }
}

class _FloodPainter extends CustomPainter {
  final Offset origin;
  final double radius;

  _FloodPainter({required this.origin, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final path = Path()
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
    canvas.save();
    canvas.clipPath(path);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (origin.dx / size.width) * 2 - 1,
            (origin.dy / size.height) * 2 - 1,
          ),
          radius: 1.0,
          colors: const [
            Color(0xDD9B8FFF),
            Color(0xCC7C6FFF),
            Color(0xBB4A3FCC),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FloodPainter old) =>
      old.radius != radius || old.origin != origin;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hold ring
// ─────────────────────────────────────────────────────────────────────────────

class _HoldRing extends StatelessWidget {
  final double progress;
  const _HoldRing({required this.progress});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _HoldRingPainter(progress: progress));
  }
}

class _HoldRingPainter extends CustomPainter {
  final double progress;
  _HoldRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      size.height / 2 + _kHoldRingCenterYOffset,
    );
    const r = 72.0;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HoldRingPainter old) =>
      old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Weight badge
// ─────────────────────────────────────────────────────────────────────────────

class _WeightBadge extends StatelessWidget {
  final double weight;
  const _WeightBadge({required this.weight});

  @override
  Widget build(BuildContext context) {
    final hasWeight = weight > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hasWeight
            ? kLogGold.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: hasWeight
              ? kLogGold.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.13),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!hasWeight)
            const Text('🏋️', style: TextStyle(fontSize: 13, height: 1))
          else
            Text(
              weight % 1 == 0
                  ? weight.toInt().toString()
                  : weight.toStringAsFixed(1),
              style: GoogleFonts.spaceMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kLogGold,
                height: 1,
              ),
            ),
          const SizedBox(width: 4),
          Text(
            'lbs',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: hasWeight
                  ? kLogGold.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.28),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top bar
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final AsyncValue<Score?> scoreAsync;
  final VoidCallback onHistoryTap;

  const _TopBar({
    required this.scoreAsync,
    required this.onHistoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: scoreAsync.when(
        data: (score) {
          final total = score?.totalScore ?? 0.0;
          final level = getLevelForScore(total);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Total: ',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4))),
                        Text(total.toStringAsFixed(0),
                            style: GoogleFonts.spaceMono(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kLogGold)),
                        Text(' pts',
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"${level.description}"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        height: 1.3,
                        color: Colors.white.withValues(alpha: 0.38),
                      ),
                    ),
                  ],
                ),
              ),
              RankBadge(level: level, size: 26, totalScore: total),
              const SizedBox(width: 8),
              Material(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: onHistoryTap,
                  borderRadius: BorderRadius.circular(9),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(
                      Icons.history_rounded,
                      size: 17,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const SizedBox(height: 36),
        error: (_, __) => const SizedBox(height: 36),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category pills
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryPills extends StatelessWidget {
  final List<Exercise> exercises;
  final List<String> recentIds;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _CategoryPills({
    required this.exercises,
    required this.recentIds,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cats = exercises.map((e) => e.category).toSet().toList()..sort();
    final all = [
      if (recentIds.isNotEmpty) _kRecentsCategory,
      ...cats,
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = all[i];
          final sel = cat == selected;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: kLogCrossfade,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? kLogPurple : kLogSurface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: sel
                    ? [BoxShadow(color: kLogPurpleGlow, blurRadius: 12)]
                    : null,
              ),
              child: Text(cat,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: sel
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                  )),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Undo bar
// ─────────────────────────────────────────────────────────────────────────────

class _UndoBar extends StatelessWidget {
  final VoidCallback onUndo;
  const _UndoBar({required this.onUndo});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: kLogSurface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text('Logged!',
              style: GoogleFonts.inter(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
          const Spacer(),
          GestureDetector(
            onTap: onUndo,
            child: Text('Undo',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kLogPurple)),
          ),
        ],
      ),
    );
  }
}
