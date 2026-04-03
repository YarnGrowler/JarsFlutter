import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'raw_notification_dom_test_button_stub.dart'
    if (dart.library.html) 'raw_notification_dom_test_button_web.dart' as impl;

/// **Web only:** embeds a real DOM button that calls
/// `Notification.requestPermission()` with no Flutter `onPressed` / gesture
/// routing — use to verify iOS PWA + manifest vs Flutter push wiring.
class RawNotificationDomTestButton extends StatelessWidget {
  const RawNotificationDomTestButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    return impl.buildRawNotificationDomTestButton();
  }
}
