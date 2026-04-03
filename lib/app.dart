import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'providers/ui_text_scale_provider.dart';
import 'router.dart';
import 'widgets/celebration/reaction_rain_host.dart';

class JarsApp extends ConsumerWidget {
  const JarsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final textScale = ref.watch(uiTextScaleProvider);

    return MaterialApp.router(
      title: 'Jars',
      debugShowCheckedModeBanner: false,
      color: JarsColors.background,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return ReactionRainHost(
          child: MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      theme: JarsTheme.dark.copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
      ),
      routerConfig: router,
    );
  }
}
