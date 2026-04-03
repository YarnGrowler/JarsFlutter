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
import 'screens/room/room_screen.dart';
import 'screens/log/log_sheet.dart';
import 'screens/log/log_history_screen.dart';
import 'screens/ranks/ranks_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'services/auth_service.dart';
import 'core/theme.dart';

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
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final session = AuthService.currentSession;
      final loc = state.matchedLocation;
      final isAuthRoute = loc.startsWith('/auth');
      // Logged-in users may open /auth/room-entry to join/create (not signup-only routes).
      final isRoomEntry = loc == '/auth/room-entry';

      final isVerifyEmail = loc == '/auth/verify-email';

      if (session == null) {
        if (isRoomEntry) return '/auth';
        if (isVerifyEmail) return null;
        if (!isAuthRoute) return '/auth';
        return null;
      }
      if (isAuthRoute && !isRoomEntry) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
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

class _ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  const _ScaffoldWithNav({required this.child});

  static const _routes = ['/', '/log', '/ranks', '/profile'];

  int _indexFromLocation(String location) {
    final idx = _routes.indexOf(location);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexFromLocation(location);

    return Scaffold(
      body: child,
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
              onTap: (index) => context.go(_routes[index]),
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
                  icon: Icon(Icons.leaderboard_outlined),
                  activeIcon: Icon(Icons.leaderboard),
                  label: 'Ranks',
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
