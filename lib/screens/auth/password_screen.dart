import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/ui/auth_shell.dart';

class PasswordScreen extends StatefulWidget {
  final String email;
  final String username;

  const PasswordScreen({
    super.key,
    required this.email,
    required this.username,
  });

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _isLogin = false;

  bool get _valid {
    if (_isLogin) return _passwordController.text.length >= 6;
    return _passwordController.text.length >= 6 &&
        _passwordController.text == _confirmController.text;
  }

  Color get _iconColor =>
      _valid && !_loading ? Colors.white : JarsColors.textTertiary;

  String _friendlyAuthError(Object e) {
    final msg = e.toString();
    if (msg.contains('over_email_send_rate_limit') ||
        msg.contains('email rate limit')) {
      return 'Too many emails sent. Wait a few minutes or use another inbox.';
    }
    if (msg.contains('User already registered') ||
        msg.contains('already been registered')) {
      return 'That email is already registered. Enter your password to sign in.';
    }
    if (msg.contains('Invalid login credentials')) {
      return 'Wrong password. Try again.';
    }
    if (msg.contains('Email not confirmed')) {
      return 'Check your inbox and confirm your email, then try again.';
    }
    if (e is StateError) {
      return e.message;
    }
    return 'Something went wrong. Try again.';
  }

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await AuthService.signIn(
          email: widget.email,
          password: _passwordController.text,
        );
      } else {
        final signRes = await AuthService.signUp(
          email: widget.email,
          username: widget.username,
          password: _passwordController.text,
        );
        if (signRes.session == null) {
          if (mounted) {
            context.go(
              '/auth/verify-email?email=${Uri.encodeComponent(widget.email)}&username=${Uri.encodeComponent(widget.username)}',
            );
          }
          return;
        }
      }
      await ProfileService.ensureProfileRow();
      await NotificationService.registerToken();
      if (mounted) {
        context.go(
          '/auth/room-entry?email=${Uri.encodeComponent(widget.email)}&username=${Uri.encodeComponent(widget.username)}',
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('User already registered') ||
            msg.contains('already been registered')) {
          setState(() {
            _isLogin = true;
            _error = _friendlyAuthError(e);
          });
        } else {
          setState(() {
            _error = _friendlyAuthError(e);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goBack() {
    context.go(
      '/auth/account?email=${Uri.encodeComponent(widget.email)}&username=${Uri.encodeComponent(widget.username)}',
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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
          onPressed: _goBack,
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
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.username,
                        style: GoogleFonts.spaceMono(
                          fontSize: 13,
                          color: JarsColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                          .animate()
                          .fadeIn(duration: 350.ms),
                      const SizedBox(height: 6),
                      Text(
                        widget.email,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: JarsColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                          .animate()
                          .fadeIn(delay: 40.ms, duration: 350.ms),
                      const SizedBox(height: 12),
                      Text(
                        _isLogin ? 'WELCOME BACK' : 'LOCK IT DOWN',
                        style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.gold,
                          letterSpacing: 1.8,
                        ),
                        textAlign: TextAlign.center,
                      )
                          .animate()
                          .fadeIn(delay: 80.ms, duration: 400.ms)
                          .slideY(begin: 0.05),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: JarsColors.primary.withValues(alpha: 0.35),
                          ),
                          color: JarsColors.surface.withValues(alpha: 0.6),
                        ),
                        child: TextField(
                          controller: _passwordController,
                          onChanged: (_) => setState(() {}),
                          autofocus: true,
                          obscureText: true,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                          ),
                          cursorColor: JarsColors.primary,
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: GoogleFonts.spaceGrotesk(
                              fontSize: 22,
                              color: JarsColors.textTertiary,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 120.ms, duration: 450.ms)
                          .slideY(begin: 0.08),
                      if (!_isLogin) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  JarsColors.border.withValues(alpha: 0.8),
                            ),
                            color: JarsColors.surface.withValues(alpha: 0.5),
                          ),
                          child: TextField(
                            controller: _confirmController,
                            onChanged: (_) => setState(() {}),
                            obscureText: true,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: JarsColors.textPrimary,
                            ),
                            cursorColor: JarsColors.primary,
                            decoration: InputDecoration(
                              hintText: 'Confirm password',
                              hintStyle: GoogleFonts.spaceGrotesk(
                                fontSize: 22,
                                color: JarsColors.textTertiary,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 12),
                            ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 450.ms)
                            .slideY(begin: 0.06),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: JarsColors.red,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 36),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _valid && !_loading ? _submit : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _valid
                                ? JarsColors.primary
                                : JarsColors.surface,
                            foregroundColor: _valid
                                ? Colors.white
                                : JarsColors.textTertiary,
                            iconColor: _iconColor,
                            elevation: _valid && !_loading ? 6 : 0,
                            shadowColor:
                                JarsColors.primary.withValues(alpha: 0.45),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _isLogin
                                          ? 'Sign in'
                                          : 'Create account',
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
                          .fadeIn(delay: 280.ms, duration: 400.ms)
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
