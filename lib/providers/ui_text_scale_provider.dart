import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final uiTextScaleProvider = NotifierProvider<UiTextScaleNotifier, double>(
  UiTextScaleNotifier.new,
);

/// Locally persisted UI text scale (0.85–1.3). Applied in [JarsApp] via [MediaQuery.textScaler].
class UiTextScaleNotifier extends Notifier<double> {
  static const _k = 'ui_text_scale';

  @override
  double build() {
    Future.microtask(_hydrate);
    return 1.0;
  }

  Future<void> _hydrate() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(_k);
    if (v != null && v >= 0.85 && v <= 1.3) {
      state = v;
    }
  }

  Future<void> setScale(double v) async {
    final c = v.clamp(0.85, 1.3);
    state = c;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_k, c);
  }
}
