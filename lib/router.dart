import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_refresh.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/account_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/password_screen.dart';
import 'screens/auth/room_entry_screen.dart';
import 'screens/auth/verify_email_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/value_slides_screen.dart';
import 'screens/onboarding/goal_question_screen.dart';
import 'screens/onboarding/frequency_question_screen.dart';
import 'screens/onboarding/crew_question_screen.dart';
import 'screens/onboarding/exercises_question_screen.dart';
import 'screens/onboarding/processing_screen.dart';
import 'screens/onboarding/notif_priming_screen.dart';
import 'screens/room/room_screen.dart';
import 'screens/log/log_sheet.dart';
import 'screens/log/log_history_screen.dart';
import 'screens/war/war_hub_screen.dart';
import 'screens/war/base_builder_screen.dart';
import 'screens/war/base_lab_screen.dart';
import 'screens/war/battle_screen.dart';
import 'screens/war/battle_report_screen.dart';
import 'screens/war/training_screen.dart';
import 'screens/ranks/ranks_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'providers/war_providers.dart';
import 'services/auth_service.dart';
import 'war/war_game.dart';
import 'war/war_types.dart';
import 'core/onboarding_campaign.dart';
import 'core/onboarding_redo.dart';
import 'core/theme.dart';
import 'widgets/ui/achievement_toast_layer.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

CustomTransitionPage<void> _fadeSlidePage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Horizontal spring-style slide for onboarding steps (trailing edge → centre).
CustomTransitionPage<void> _onboardingSlide(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final forward = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final back = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1.0, 0),
          end: Offset.zero,
        ).animate(forward),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.25, 0),
          ).animate(back),
          child: FadeTransition(
            opacity: forward,
            child: child,
          ),
        ),
      );
    },
  );
}

final authRefreshNotifierProvider = Provider<AuthRefreshNotifier>((ref) {
  final n = AuthRefreshNotifier();
  ref.onDispose(n.dispose);
  return n;
});

final routerProvider = Provider<GoRouter>((ref) {
  final authRefresh = ref.watch(authRefreshNotifierProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: Listenable.merge([
      authRefresh,
      OnboardingCampaign.gate,
    ]),
    redirect: (context, state) {
      final session = AuthService.currentSession;
      // Use the real path — matchedLocation for nested /auth/* routes can be `/auth`,
      // which breaks auth detection and triggers the wrong redirects.
      final path = state.uri.path;
      final isAuthRoute = path.startsWith('/auth');
      final isOnboardingRoute = path.startsWith('/onboarding');
      // Logged-in users may open /auth/room-entry to join/create (not signup-only routes).
      final isRoomEntry = path == '/auth/room-entry';
      final isVerifyEmail = path == '/auth/verify-email';

      final campaign = OnboardingCampaign.isCampaignActive;
      final slidesDone = OnboardingCampaign.slidesCompleted;
      final mustSeeIntroSlides = campaign && !slidesDone;

      // Signed-in users: until slides are done (campaign), always open onboarding first.
      if (session != null && mustSeeIntroSlides) {
        if (path == '/onboarding/notifications') return null;
        if (!isOnboardingRoute) return '/onboarding';
        return null;
      }

      if (session == null) {
        if (isRoomEntry) return '/onboarding';
        if (isVerifyEmail) return null;
        if (isOnboardingRoute) {
          if (path == '/onboarding' && campaign && slidesDone) {
            return '/onboarding/q1';
          }
          return null;
        }
        if (!isAuthRoute) {
          if (campaign && slidesDone) return '/onboarding/q1';
          return '/onboarding';
        }
        return null;
      }
      // Logged-in users: onboarding is blocked except post-signup notif priming,
      // intro campaign (handled above), or replay from settings.
      if (isOnboardingRoute &&
          path != '/onboarding/notifications' &&
          !OnboardingRedoSession.active) {
        return '/';
      }
      if (isAuthRoute && !isRoomEntry) return '/';
      return null;
    },
    routes: [
      // ── Onboarding flow (logged-out only) ──────────────────────────────
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => _onboardingSlide(
          state,
          const WelcomeScreen(),
        ),
        routes: [
          GoRoute(
            path: 'value',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const ValueSlidesScreen(),
            ),
          ),
          GoRoute(
            path: 'q1',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const GoalQuestionScreen(),
            ),
          ),
          GoRoute(
            path: 'q2',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const FrequencyQuestionScreen(),
            ),
          ),
          GoRoute(
            path: 'q3',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const ExercisesQuestionScreen(),
            ),
          ),
          GoRoute(
            path: 'q4',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const CrewQuestionScreen(),
            ),
          ),
          GoRoute(
            path: 'processing',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const ProcessingScreen(),
            ),
          ),
          GoRoute(
            path: 'notifications',
            pageBuilder: (context, state) => _onboardingSlide(
              state,
              const NotifPrimingScreen(),
            ),
          ),
        ],
      ),

      // ── Legacy /auth entry (redirect → new onboarding welcome) ─────────
      GoRoute(
        path: '/auth',
        redirect: (context, state) {
          // Only the bare /auth URL (legacy entry). Do NOT use matchedLocation:
          // for /auth/login, /auth/account, etc. it can still be `/auth`, which
          // incorrectly sent every auth screen to /onboarding.
          if (state.uri.path == '/auth') return '/onboarding';
          return null;
        },
        pageBuilder: (context, state) => _fadeSlidePage(
          state,
          const OnboardingScreen(),
        ),
        routes: [
          GoRoute(
            path: 'login',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const LoginScreen(),
            ),
          ),
          GoRoute(
            path: 'username',
            redirect: (context, state) => '/auth/account',
          ),
          GoRoute(
            path: 'account',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const AccountScreen(),
            ),
          ),
          GoRoute(
            path: 'password',
            pageBuilder: (context, state) {
              final email = state.uri.queryParameters['email'] ?? '';
              final username = state.uri.queryParameters['username'] ?? '';
              return _fadeSlidePage(
                state,
                PasswordScreen(email: email, username: username),
              );
            },
          ),
          GoRoute(
            path: 'verify-email',
            pageBuilder: (context, state) {
              final email = state.uri.queryParameters['email'] ?? '';
              final username = state.uri.queryParameters['username'] ?? '';
              return _fadeSlidePage(
                state,
                VerifyEmailScreen(email: email, username: username),
              );
            },
          ),
          GoRoute(
            path: 'room-entry',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const RoomEntryScreen(),
            ),
          ),
        ],
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => _ScaffoldWithNav(child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: RoomScreen(),
            ),
          ),
          GoRoute(
            path: '/log',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LogSheet(),
            ),
          ),
          GoRoute(
            path: '/log-history',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const LogHistoryScreen(),
            ),
          ),
          GoRoute(
            path: '/ranks',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: RanksScreen(),
            ),
          ),
          GoRoute(
            path: '/war',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WarHubScreen(),
            ),
          ),
          GoRoute(
            path: '/war/build',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const BaseBuilderScreen(),
            ),
          ),
          GoRoute(
            path: '/war/battle',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              BattleScreen(
                  mode: state.uri.queryParameters['mode'] ?? 'attack'),
            ),
          ),
          GoRoute(
            path: '/war/report',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const BattleReportScreen(),
            ),
          ),
          GoRoute(
            path: '/war/train',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const TrainingScreen(),
            ),
          ),
          GoRoute(
            path: '/war/lab',
            pageBuilder: (context, state) => _fadeSlidePage(
              state,
              const BaseLabScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});

// Keeps the shared Clan War state synced app-wide, not just while a War
// screen is on-screen. `warRoomSyncProvider` is a plain (non-autoDispose)
// FutureProvider, so Riverpod never instantiates it until something
// watches it — if that only ever happened inside War screens, a player who
// logs a workout without ever opening the War tab this session would have
// `WarGame.instance.roomId` still null, silently earning zero war points.
// Watching it once, here, on the shell that's mounted for the whole
// authenticated app regardless of which tab is showing, closes that gap.
//
// ALSO drives the wall-clock catch-up (`syncToWallClock`) — previously that
// only ever fired from war_hub_screen's initState + its own 1s ticker, so a
// player who navigated straight to the battle/defense screen (or just sat
// there instead of the hub) never got the enemy's already-happened raids
// simulated locally: the feed stayed stale and "WATCH" replay buttons found
// nothing, even hours into a war that had genuinely moved on. Ticking it
// here too means every screen — not just the hub — comes home to a war
// that kept going, with no detour through the hub required.
class _WarSyncKeepAlive extends ConsumerStatefulWidget {
  const _WarSyncKeepAlive();

  @override
  ConsumerState<_WarSyncKeepAlive> createState() => _WarSyncKeepAliveState();
}

class _WarSyncKeepAliveState extends ConsumerState<_WarSyncKeepAlive> {
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WarGame.instance.syncToWallClock();
    });
    // cheap when nothing new has happened (an early return before any real
    // work) — matches the hub's own polling cadence so a raid landing while
    // you're elsewhere still shows up within a second of it happening.
    _clockTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (WarGame.instance.phase == WarPhase.war) {
        WarGame.instance.syncToWallClock();
      }
    });
  }

  @override
  void dispose() {
    _clockTick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(warRoomSyncProvider);
    return const SizedBox.shrink();
  }
}

class _ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  const _ScaffoldWithNav({required this.child});

  static const _routes = ['/', '/log', '/war', '/profile'];

  int _indexFromLocation(String location) {
    final idx = _routes.indexOf(location);
    if (idx >= 0) return idx;
    // keep the tab lit on nested routes (e.g. /war/build → War tab)
    for (var i = 1; i < _routes.length; i++) {
      if (location.startsWith('${_routes[i]}/')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexFromLocation(location);

    final shell = _buildShell(context, currentIndex);
    // Phone frame on wide viewports (desktop web): the app is a mobile game —
    // clamp it to a centered handset-width column instead of stretching bars
    // across the whole monitor.
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 600) return shell;
    return ColoredBox(
      color: const Color(0xFF030308),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 470),
          decoration: BoxDecoration(
            border: Border.symmetric(
              vertical: BorderSide(
                color: JarsColors.border.withValues(alpha: 0.6),
              ),
            ),
          ),
          child: shell,
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context, int currentIndex) {
    return Scaffold(
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          const AchievementToastLayer(),
          const _WarSyncKeepAlive(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: JarsColors.background,
          border: const Border(
            top: BorderSide(color: JarsColors.border, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: (index) {
                // Modal bottom sheets are on the shell navigator; `context` here may not
                // be the same Navigator that hosted the sheet, so pop via shell key.
                final shellCtx = _shellNavigatorKey.currentContext;
                if (shellCtx != null) {
                  final nav = Navigator.of(shellCtx);
                  for (var i = 0; i < 16 && nav.canPop(); i++) {
                    nav.pop();
                  }
                }
                context.go(_routes[index]);
              },
              iconSize: 24,
              selectedFontSize: 11,
              unselectedFontSize: 11,
              showUnselectedLabels: true,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: JarsColors.primary,
              unselectedItemColor: JarsColors.textTertiary,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Room',
                ),
                BottomNavigationBarItem(
                  icon: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 6),
                    decoration: BoxDecoration(
                      color: currentIndex == 1
                          ? JarsColors.primary
                          : JarsColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Icon(
                      Icons.fitness_center,
                      color: currentIndex == 1
                          ? Colors.white
                          : JarsColors.primary,
                      size: 22,
                    ),
                  ),
                  label: 'Log',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.shield_outlined),
                  activeIcon: Icon(Icons.shield),
                  label: 'War',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'You',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
