import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/ui/auth_shell.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String username;

  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.username,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resendBusy = false;
  String? _error;
  int _cooldownSec = 0;
  Timer? _cooldownTimer;

  bool get _valid =>
      _codeController.text.trim().length >= 6 &&
      _codeController.text.trim().length <= 12;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSec = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _cooldownSec--;
        if (_cooldownSec <= 0) t.cancel();
      });
    });
  }

  String _friendly(Object e) {
    final msg = e.toString();
    if (msg.contains('expired') || msg.contains('invalid')) {
      return 'That code is wrong or expired. Request a new one.';
    }
    if (msg.contains('rate') || msg.contains('over_email')) {
      return 'Too many attempts. Wait a few minutes.';
    }
    return 'Could not verify. Check the code and try again.';
  }

  Future<void> _verify() async {
    if (!_valid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.verifySignupOtp(
        email: widget.email,
        token: _codeController.text.trim(),
      );
      await ProfileService.ensureProfileRow();
      if (!mounted) return;
      context.go(
        '/auth/room-entry?email=${Uri.encodeComponent(widget.email)}&username=${Uri.encodeComponent(widget.username)}',
      );
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldownSec > 0 || _resendBusy) return;
    setState(() {
      _resendBusy = true;
      _error = null;
    });
    try {
      await AuthService.resendSignupOtp(email: widget.email);
      if (mounted) {
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'New code sent to ${widget.email}',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: JarsColors.surface,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
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
          onPressed: () => context.go(
            '/auth/password?email=${Uri.encodeComponent(widget.email)}&username=${Uri.encodeComponent(widget.username)}',
          ),
        ),
      ),
      body: AuthShell(
        child: SafeArea(
          top: true,
          bottom: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      Text(
                        'CHECK YOUR INBOX',
                        style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.gold,
                          letterSpacing: 1.6,
                        ),
                      ).animate().fadeIn(duration: 350.ms),
                      const SizedBox(height: 16),
                      Text(
                        'Enter the confirmation code we sent you.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: JarsColors.textPrimary,
                          height: 1.25,
                        ),
                      ).animate().fadeIn(delay: 40.ms, duration: 400.ms),
                      const SizedBox(height: 12),
                      Text(
                        widget.email,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: JarsColors.textSecondary,
                        ),
                      ).animate().fadeIn(delay: 70.ms, duration: 400.ms),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: JarsColors.primary.withValues(alpha: 0.45),
                          ),
                          color: JarsColors.surface.withValues(alpha: 0.6),
                        ),
                        child: TextField(
                          controller: _codeController,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          maxLength: 8,
                          textAlign: TextAlign.center,
                          autofocus: true,
                          style: GoogleFonts.spaceMono(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                            letterSpacing: 6,
                          ),
                          cursorColor: JarsColors.primary,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            hintStyle: GoogleFonts.spaceMono(
                              fontSize: 28,
                              color: JarsColors.textTertiary,
                              letterSpacing: 6,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                        ),
                      ).animate().fadeIn(delay: 100.ms, duration: 450.ms),
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
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _valid && !_loading ? _verify : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _valid
                                ? JarsColors.primary
                                : JarsColors.surface,
                            foregroundColor: _valid
                                ? Colors.white
                                : JarsColors.textTertiary,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Verify & continue',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: (_cooldownSec > 0 || _resendBusy)
                            ? null
                            : _resend,
                        child: Text(
                          _cooldownSec > 0
                              ? 'Resend code (${_cooldownSec}s)'
                              : 'Resend code',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _cooldownSec > 0
                                ? JarsColors.textTertiary
                                : JarsColors.primary,
                          ),
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
