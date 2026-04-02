import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../widgets/sheets/room_sheets.dart';
import '../../widgets/ui/auth_shell.dart';

class RoomEntryScreen extends ConsumerWidget {
  const RoomEntryScreen({super.key});

  void _goBack(BuildContext context) {
    final q = GoRouterState.of(context).uri.queryParameters;
    final email = q['email'] ?? '';
    final username = q['username'] ?? '';
    if (email.isNotEmpty) {
      context.go(
        '/auth/password?email=${Uri.encodeComponent(email)}&username=${Uri.encodeComponent(username)}',
      );
    } else {
      context.go('/auth/account');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: JarsColors.textSecondary,
          onPressed: () => _goBack(context),
        ),
      ),
      body: AuthShell(
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Pick your battlefield',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                )
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                const SizedBox(height: 8),
                Text(
                  'Join with a code or start a new room',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: JarsColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                )
                    .animate()
                    .fadeIn(delay: 80.ms, duration: 400.ms),
                const SizedBox(height: 32),
                _RoomActionTile(
                  icon: Icons.vpn_key_rounded,
                  title: 'Join with code',
                  subtitle: 'Enter your crew’s 6-character invite',
                  onTap: () => showJoinRoomSheet(context),
                )
                    .animate()
                    .fadeIn(delay: 120.ms, duration: 400.ms)
                    .slideX(begin: 0.04),
                const SizedBox(height: 14),
                _RoomActionTile(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Create a room',
                  subtitle: 'You’re the host — set size and name',
                  onTap: () => showCreateRoomSheet(context),
                )
                    .animate()
                    .fadeIn(delay: 180.ms, duration: 400.ms)
                    .slideX(begin: 0.04),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: Text(
                    'Skip for now',
                    style: GoogleFonts.inter(
                      color: JarsColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoomActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: JarsColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: JarsColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: JarsColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: JarsColors.primary, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: JarsColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: JarsColors.textTertiary,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
