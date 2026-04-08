// Single source of truth: what notifications exist, how they fire, and status.
// Delivery: rows in public.notifications → DB webhook / Edge → FCM or Web Push.

/// User-visible notification kinds (conceptual — body text varies).
enum JarsNotificationKind {
  /// SQL `notify_room_on_wake_card` after `__WAKE__|` feed insert.
  idleWakeRoom,

  /// RPC `send_wake_nudge` — to the absent member only.
  wakeNudgeToAbsent,

  /// [EventService] — user passed someone in points.
  overtakeVictim,

  /// [EventService] — everyone else in room.
  overtakeSpectators,

  /// [EventService] — PR broadcast.
  personalRecordRoom,

  /// [EventService] — first real log of Chicago calendar day.
  firstLogOfDayRoom,

  /// [EventService] — streak milestone 3/7/14/…
  streakMilestoneRoom,

  /// [EventService] — streak broken / dead streak taunt.
  deadStreakRoom,

  /// [EventService] — close the gap taunt.
  closeGapRoom,

  // ── Cron / Edge (scheduled) ────────────────────────────────────────
  /// Push when `daily_points < streak_minimum` near end of Chicago day.
  streakMinimumAtRisk,

  /// Reminder when user has not logged today and wall-clock is near yesterday’s
  /// first-log time (Chicago calendar day).
  sameTimeYesterdayReminder,
}

/// Whether the app currently sends this kind (DB + Flutter + Edge).
class JarsNotificationStatus {
  final JarsNotificationKind kind;
  final bool implemented;

  /// Short note for humans (e.g. "needs pg_cron + Edge").
  final String detail;

  const JarsNotificationStatus({
    required this.kind,
    required this.implemented,
    this.detail = '',
  });
}

/// Inventory for product / support. Keep in sync with code + SQL.
const List<JarsNotificationStatus> kJarsNotificationInventory = [
  JarsNotificationStatus(
    kind: JarsNotificationKind.idleWakeRoom,
    implemented: true,
    detail: 'Trigger: insert __WAKE__| row; patch 20 skips never-logged users.',
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.wakeNudgeToAbsent,
    implemented: true,
    detail: 'RPC send_wake_nudge; max 2 taps per card.',
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.overtakeVictim,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.overtakeSpectators,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.personalRecordRoom,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.firstLogOfDayRoom,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.streakMilestoneRoom,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.deadStreakRoom,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.closeGapRoom,
    implemented: true,
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.streakMinimumAtRisk,
    implemented: true,
    detail:
        'Edge `cron-streak-nudge` + SQL `cron_streak_nudge_execute`; schedule POST with CRON_SECRET; see docs/NOTIFICATIONS.md.',
  ),
  JarsNotificationStatus(
    kind: JarsNotificationKind.sameTimeYesterdayReminder,
    implemented: false,
    detail:
        'Needs stored "first log time" per user + daily scheduler; not implemented.',
  ),
];
