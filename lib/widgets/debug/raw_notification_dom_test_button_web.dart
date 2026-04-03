import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Real DOM `<button>` → `Notification.requestPermission()` (no Flutter gesture arena).
Widget buildRawNotificationDomTestButton() {
  return const _RawDomButtonHost();
}

class _RawDomButtonHost extends StatefulWidget {
  const _RawDomButtonHost();

  @override
  State<_RawDomButtonHost> createState() => _RawDomButtonHostState();
}

class _RawDomButtonHostState extends State<_RawDomButtonHost> {
  static bool _factoryRegistered = false;
  static const String _viewType = 'jars-raw-notification-permission-test';

  @override
  void initState() {
    super.initState();
    if (!_factoryRegistered) {
      _factoryRegistered = true;
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        final root = html.DivElement()
          ..style.width = '100%'
          ..style.boxSizing = 'border-box';

        final hint = html.ParagraphElement()
          ..text =
              'PWA check: this is a native HTML button (not Flutter). If the '
              'system prompt appears here but not from Profile → notifications, '
              'the Flutter layer is eating the user gesture.'
          ..style.color = '#a1a1aa'
          ..style.fontSize = '12px'
          ..style.margin = '0 0 10px 0'
          ..style.lineHeight = '1.4'
          ..style.textAlign = 'center';

        final btn = html.ButtonElement()
          ..type = 'button'
          ..text = 'TEST: Raw Notification.requestPermission()'
          ..style.boxSizing = 'border-box'
          ..style.width = '100%'
          ..style.padding = '14px'
          ..style.fontSize = '15px'
          ..style.fontWeight = '700'
          ..style.cursor = 'pointer'
          ..style.borderRadius = '14px'
          ..style.border = 'none'
          ..style.backgroundColor = '#7c3aed'
          ..style.color = '#ffffff'
          ..onClick.listen((html.MouseEvent e) {
            e.stopPropagation();
            e.preventDefault();
            html.Notification.requestPermission().then((result) {
              html.window.console.log('Raw Notification.requestPermission → $result');
              html.window.alert('Raw Notification.requestPermission → $result');
            });
          });

        root.children.add(hint);
        root.children.add(btn);
        return root;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        height: 132,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
