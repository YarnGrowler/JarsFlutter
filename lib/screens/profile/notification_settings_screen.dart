import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/fcm_device.dart';
import '../../services/notification_service.dart';

/// Request push permission (important for iPhone “Add to Home Screen” web apps),
/// list registered FCM endpoints, and revoke them.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _loading = true;
  bool _busy = false;
  /// Sync guard only (no [setState] before [registerToken] — preserves web gesture).
  bool _enableInFlight = false;
  NotificationSettings? _settings;
  List<FcmDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    NotificationSettings? s;
    List<FcmDevice> d = [];
    try {
      final batch = await Future.wait([
        NotificationService.getNotificationSettings(),
        NotificationService.listMyDevices(),
      ]).timeout(const Duration(seconds: 12));
      s = batch[0] as NotificationSettings?;
      d = batch[1] as List<FcmDevice>;
    } on TimeoutException {
      s = null;
      d = [];
    } catch (_) {
      s = null;
      d = [];
    }
    if (!mounted) return;
    setState(() {
      _settings = s;
      _devices = d;
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    if (_enableInFlight) return;
    _enableInFlight = true;
    // Do not call [setState] before this await — rebuild work can break the
    // user-gesture chain for [Notification.requestPermission] on iOS PWA.
    final ok = await NotificationService.registerToken();
    _enableInFlight = false;
    if (!mounted) return;
    setState(() {});
    await _refresh();
    if (!mounted) return;
    final err = NotificationService.lastRegisterTokenError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'This device was registered for push. On iPhone, the system prompt only appears when you tap this button — choose Allow.'
              : err ??
                  'Could not enable push. On iPhone (Home Screen): if you never saw a prompt, an older visit may have blocked it — try Settings → Apps → Jars / Safari → Notifications, or remove the Home Screen icon and add it again. Then open the app and tap this button once.',
          style: GoogleFonts.inter(),
        ),
        backgroundColor: ok ? null : JarsColors.red,
      ),
    );
  }

  Future<void> _revoke(FcmDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text(
          'Revoke this device?',
          style: GoogleFonts.spaceGrotesk(color: JarsColors.textPrimary),
        ),
        content: Text(
          'Push will stop for that browser or phone until you enable notifications there again.',
          style: GoogleFonts.inter(
            color: JarsColors.textSecondary,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Revoke',
              style: GoogleFonts.inter(
                color: JarsColors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final success = await NotificationService.revokeDevice(d);
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Device removed from push.' : 'Could not remove device.',
          style: GoogleFonts.inter(),
        ),
      ),
    );
  }

  bool _isThisDevice(FcmDevice d) {
    final c = NotificationService.cachedLocalFcmToken;
    return c != null && c == d.token;
  }

  @override
  Widget build(BuildContext context) {
    final status = _settings?.authorizationStatus;
    final statusLabel = status == null
        ? 'Unknown — tap Enable to refresh'
        : NotificationService.describeAuthorization(status);

    return Scaffold(
      backgroundColor: JarsColors.surface,
      appBar: AppBar(
        backgroundColor: JarsColors.surface,
        foregroundColor: JarsColors.textPrimary,
        title: Text(
          'Notifications',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed:
                _loading || _busy || _enableInFlight ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Text(
                      'Permission: $statusLabel',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // MagicBell-style: one obvious control = system “allow notifications?” sheet
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: JarsColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: JarsColors.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: JarsColors.primary
                                        .withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.notifications_active_rounded,
                                    color: JarsColors.primary,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Allow notifications',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: JarsColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        status == AuthorizationStatus.denied
                                            ? 'This device blocked alerts before. Turn them on in Settings, then tap below to register with Jars.'
                                            : 'Tap the button — your phone or browser will show the “allow notifications?” prompt (like other apps).',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: JarsColors.textSecondary,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: JarsColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: (_busy || _enableInFlight)
                                    ? null
                                    : _enableNotifications,
                                child: (_busy || _enableInFlight)
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        status ==
                                                AuthorizationStatus.denied
                                            ? 'I turned them on in Settings — register'
                                            : 'Show permission prompt',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'After you allow, we save this device for rank-ups, wake pings, and room activity.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: JarsColors.textTertiary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(height: 14),
                      Text(
                        'iPhone / iPad (Home Screen): the prompt only appears from this button — '
                        'not on login. Add Jars with “Add to Home Screen” and use a valid PWA '
                        '(manifest + standalone) so Jars appears under Settings → Notifications.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: JarsColors.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'Registered devices',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Each browser or phone keeps its own token. Revoke ones you no longer use.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: JarsColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No devices saved yet. Tap the button above after signing in.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: JarsColors.textTertiary,
                          ),
                        ),
                      )
                    else
                      ..._devices.map((d) {
                        final seenAt = d.lastSeenAt;
                        final seen = seenAt != null
                            ? DateFormat.MMMd()
                                .add_jm()
                                .format(seenAt.toLocal())
                            : '—';
                        final here = _isThisDevice(d);
                        return Card(
                          color: JarsColors.surfaceRaised,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    d.platform.toUpperCase(),
                                    style: GoogleFonts.spaceMono(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: JarsColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (here)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: JarsColors.primary.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'This device',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: JarsColors.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.shortToken,
                                    style: GoogleFonts.spaceMono(
                                      fontSize: 11,
                                      color: JarsColors.textTertiary,
                                    ),
                                  ),
                                  Text(
                                    'Last seen $seen',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: JarsColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: TextButton(
                              onPressed: _busy ? null : () => _revoke(d),
                              child: Text(
                                'Revoke',
                                style: GoogleFonts.inter(
                                  color: JarsColors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
