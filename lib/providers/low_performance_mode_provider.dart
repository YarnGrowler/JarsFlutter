import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final lowPerformanceModeProvider =
    NotifierProvider<LowPerformanceModeNotifier, bool>(
  LowPerformanceModeNotifier.new,
);

/// Locally persisted — off by default. Read by the war screens to skip
/// ambient/particle animation and force the board's existing low-detail
/// (zoomed-out) render path regardless of actual zoom, for older devices.
class LowPerformanceModeNotifier extends Notifier<bool> {
  static const _k = 'low_performance_mode';

  @override
  bool build() {
    Future.microtask(_hydrate);
    return false;
  }

  Future<void> _hydrate() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getBool(_k);
    if (v != null) state = v;
  }

  Future<void> setEnabled(bool v) async {
    state = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_k, v);
  }
}
