import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../widgets/ui/auth_shell.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final q = GoRouterState.of(context).uri.queryParameters;
      final email = q['email'];
      final username = q['username'];
      if (email != null && email.isNotEmpty) {
        _emailController.text = email;
      }
      if (username != null && username.isNotEmpty) {
        _usernameController.text = username;
      }
      setState(() {});
    });
    _emailController.addListener(_onFieldChanged);
    _usernameController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  bool get _valid {
    final u = _usernameController.text.trim();
    return isValidEmailFormat(_emailController.text) && u.length >= 3;
  }

  Color get _iconColor =>
      _valid ? Colors.white : JarsColors.textTertiary;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_valid) return;
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    context.go(
      '/auth/password?email=${Uri.encodeComponent(email)}&username=${Uri.encodeComponent(username)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          color: JarsColors.textSecondary,
          onPressed: () => context.go('/auth'),
        ),
      ),
      body: AuthShell(
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'YOUR ACCOUNT',
                        style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.gold,
                          letterSpacing: 1.8,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      )
                          .animate()
                          .fadeIn(duration: 450.ms)
                          .slideY(begin: 0.06, curve: Curves.easeOutCubic),
                      const SizedBox(height: 8),
                      Text(
                        'Email is for sign-in. Display name is your username in rooms and on the board.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: JarsColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      )
                          .animate()
                          .fadeIn(delay: 80.ms, duration: 400.ms),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofocus: true,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.textPrimary,
                        ),
                        cursorColor: JarsColors.primary,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          labelStyle: GoogleFonts.inter(
                            color: JarsColors.textSecondary,
                          ),
                          hintStyle: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            color: JarsColors.textTertiary,
                          ),
                          filled: true,
                          fillColor: JarsColors.surface.withValues(alpha: 0.65),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: JarsColors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: JarsColors.border.withValues(alpha: 0.9),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: JarsColors.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 120.ms, duration: 450.ms)
                          .slideY(begin: 0.08),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        textCapitalization: TextCapitalization.words,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: JarsColors.textPrimary,
                        ),
                        cursorColor: JarsColors.primary,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          hintText: 'Shown in rooms & leaderboard',
                          labelStyle: GoogleFonts.inter(
                            color: JarsColors.textSecondary,
                          ),
                          hintStyle: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textTertiary,
                          ),
                          filled: true,
                          fillColor: JarsColors.surface.withValues(alpha: 0.65),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: JarsColors.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: JarsColors.border.withValues(alpha: 0.9),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: JarsColors.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 180.ms, duration: 450.ms)
                          .slideY(begin: 0.06),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _valid ? _continue : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _valid
                                ? JarsColors.primary
                                : JarsColors.surface,
                            foregroundColor: _valid
                                ? Colors.white
                                : JarsColors.textTertiary,
                            iconColor: _iconColor,
                            elevation: _valid ? 6 : 0,
                            shadowColor:
                                JarsColors.primary.withValues(alpha: 0.45),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 22,
                                color: _iconColor,
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 260.ms, duration: 450.ms)
                          .slideY(begin: 0.1),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
