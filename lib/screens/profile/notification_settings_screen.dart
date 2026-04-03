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
  NotificationSettings? _settings;
  List<FcmDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final s = await NotificationService.getNotificationSettings();
    final d = await NotificationService.listMyDevices();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _devices = d;
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    setState(() => _busy = true);
    final ok = await NotificationService.registerToken();
    if (!mounted) return;
    setState(() => _busy = false);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'This device was registered for push. If you use Safari / “Add to Home Screen”, approve the prompt when it appears.'
              : 'Could not enable push. If permission was denied, open system settings for this app or site and allow notifications, then try again.',
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
        ? '…'
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
            onPressed: _loading || _busy ? null : _refresh,
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
                    if (kIsWeb) ...[
                      const SizedBox(height: 8),
                      Text(
                        'If you added Jars to your iPhone Home Screen, open the app and tap '
                        'the button below — iOS often will not show a notification prompt until you do.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: JarsColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _enableNotifications,
                        icon: _busy
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.notifications_active_outlined),
                        label: Text(
                          status == AuthorizationStatus.denied
                              ? 'Open settings — then try again'
                              : 'Enable / register this device',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (status == AuthorizationStatus.denied) ...[
                      const SizedBox(height: 8),
                      Text(
                        'This OS already denied alerts. On iPhone: Settings → Apps (or Notifications) → '
                        'Safari / your browser or the Jars app → allow notifications.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: JarsColors.textTertiary,
                          height: 1.35,
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
                        final seen = d.lastSeenAt != null
                            ? DateFormat.MMMd().add_jm().format(d.lastSeenAt!.toLocal())
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
