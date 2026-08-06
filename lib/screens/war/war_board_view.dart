import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../../war/war_base.dart';
import '../../war/war_types.dart';
import 'war_board.dart';

/// Lets a screen KICK the camera — mortar impacts rattle the world.
class WarBoardController {
  _WarBoardViewState? _state;
  void kick(double power) => _state?._kick(power);
}

/// A scrolling, zoomable camera over the battlefield.
/// - Drag to pan · pinch to zoom (touch)
/// - Mouse wheel to zoom · WASD / arrow keys to pan (web/desktop)
/// - On-screen + / − / ⛶ controls
class WarBoardView extends StatefulWidget {
  final Base base;
  final WarBoardPainter Function(double tile, double gx, double gy, double t)
      painterBuilder;

  /// Optional second painter drawn over the board with the same camera
  /// transform (combat FX, projectiles, damage numbers).
  final CustomPainter? Function(double tile, double gx, double gy, double t)?
      overlayBuilder;
  final void Function(Cell cell)? onCellTap;

  /// Called every animation frame with the elapsed delta (drive battles/FX).
  final void Function(double dt)? onTick;
  final bool startFitted; // open showing the whole map
  final Cell? startFocus; // else center here at 1× zoom
  final WarBoardController? controller; // screen shake hookup
  /// Optional fixed repaint cap for experimental high-motion views. Simulation
  /// still ticks every frame; only painting is capped.
  final int? animationFps;

  /// Profile → Low performance mode: mutes camera shake and always uses the
  /// board's existing low-detail repaint throttle, regardless of zoom.
  final bool lowPerformanceMode;

  const WarBoardView({
    super.key,
    required this.base,
    required this.painterBuilder,
    this.overlayBuilder,
    this.onCellTap,
    this.onTick,
    this.startFitted = false,
    this.startFocus,
    this.controller,
    this.animationFps,
    this.lowPerformanceMode = false,
  });

  @override
  State<WarBoardView> createState() => _WarBoardViewState();
}

class _WarBoardViewState extends State<WarBoardView>
    with SingleTickerProviderStateMixin {
  static const double baseTile = 50;
  static const double _maxZoom = 2.2;
  static const double _panSpeed = 520; // screen px/s for key panning

  late final Ticker _ticker;
  double _t = 0, _last = 0;
  double _paintAccum = 0;
  double _zoom = 1;
  Offset _offset = Offset.zero; // world(zoomed) px scrolled past the top-left
  double _minZoom = 0.4;
  Size _viewport = Size.zero;
  bool _inited = false;
  double _lastScale = 1;
  final Set<LogicalKeyboardKey> _keys = {};
  final FocusNode _focus = FocusNode();

  double get _tile => baseTile * _zoom;
  double get _worldW => widget.base.cols * baseTile;
  double get _worldH => widget.base.rows * baseTile;

  double _shakeAmp = 0; // camera rattle (mortar hits)

  void _kick(double power) {
    if (widget.lowPerformanceMode) return;
    _shakeAmp = math.max(_shakeAmp, power.clamp(0, 14));
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _ticker = createTicker((elapsed) {
      final now = elapsed.inMicroseconds / 1e6;
      final dt = (now - _last).clamp(0.0, 0.05);
      _last = now;
      _t = now;
      _keyPan(dt);
      if (_shakeAmp > 0) _shakeAmp = math.max(0, _shakeAmp - dt * 26);
      widget.onTick?.call(dt);
      final requestedFps = widget.animationFps;
      if (requestedFps != null && _shakeAmp <= 0) {
        _paintAccum += dt;
        if (_paintAccum < 1 / requestedFps.clamp(1, 60)) return;
        _paintAccum = 0;
        if (mounted) setState(() {});
        return;
      }
      // Big boards + zoomed out: ambient motion is frozen in the painter, so
      // repainting 60×/sec just burns CPU. Drop to ~6–8 fps unless shaking.
      // Low performance mode forces this path unconditionally.
      final tile = baseTile * _zoom;
      final bigBoard = widget.base.rows >= 52;
      final lod =
          widget.lowPerformanceMode || tile < 22 || (bigBoard && tile < 28);
      if (lod && _shakeAmp <= 0) {
        _paintAccum += dt;
        if (_paintAccum < (tile < 14 ? 0.2 : 0.14)) return;
        _paintAccum = 0;
      } else {
        _paintAccum = 0;
      }
      if (mounted) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _init(Size vp) {
    _viewport = vp;
    _minZoom =
        (math.min(vp.width / _worldW, vp.height / _worldH) * 0.98).clamp(0.1, 1.0);
    if (_inited) {
      _clamp();
      return;
    }
    _inited = true;
    if (widget.startFitted) {
      _zoom = _minZoom;
      _clamp();
    } else {
      _zoom = 1.0.clamp(_minZoom, _maxZoom);
      final f = widget.startFocus;
      if (f != null) {
        _offset = Offset(
          (f.c + 0.5) * _tile - vp.width / 2,
          (f.r + 0.5) * _tile - vp.height / 2,
        );
      }
      _clamp();
    }
  }

  void _clamp() {
    final w = _worldW * _zoom, h = _worldH * _zoom;
    // generous overscroll: any edge tile can be brought to screen CENTER, and
    // the camera drifts onto the scenery skirt (CoC-style breathing room)
    double axis(double off, double world, double view) {
      final margin = math.min(view * 0.45, 7 * _tile);
      if (world <= view) return (world - view) / 2; // center small worlds
      return off.clamp(-margin, world - view + margin);
    }

    _offset = Offset(
      axis(_offset.dx, w, _viewport.width),
      axis(_offset.dy, h, _viewport.height),
    );
  }

  void _zoomAt(Offset focal, double factor) {
    final old = _zoom;
    _zoom = (_zoom * factor).clamp(_minZoom, _maxZoom);
    if (_zoom == old) return;
    final k = _zoom / old;
    _offset = (_offset + focal) * k - focal;
    _clamp();
  }

  void _keyPan(double dt) {
    if (_keys.isEmpty) return;
    var dx = 0.0, dy = 0.0;
    if (_keys.contains(LogicalKeyboardKey.keyA) ||
        _keys.contains(LogicalKeyboardKey.arrowLeft)) {
      dx -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyD) ||
        _keys.contains(LogicalKeyboardKey.arrowRight)) {
      dx += 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyW) ||
        _keys.contains(LogicalKeyboardKey.arrowUp)) {
      dy -= 1;
    }
    if (_keys.contains(LogicalKeyboardKey.keyS) ||
        _keys.contains(LogicalKeyboardKey.arrowDown)) {
      dy += 1;
    }
    if (dx == 0 && dy == 0) return;
    _offset += Offset(dx, dy) * _panSpeed * dt;
    _clamp();
  }

  Cell? _cellAt(Offset local) {
    final c = ((local.dx + _offset.dx) / _tile).floor();
    final r = ((local.dy + _offset.dy) / _tile).floor();
    if (r < 0 || r >= widget.base.rows || c < 0 || c >= widget.base.cols) {
      return null;
    }
    return Cell(r, c);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cns) {
      _init(Size(cns.maxWidth, cns.maxHeight));
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, e) {
          final wanted = {
            LogicalKeyboardKey.keyW,
            LogicalKeyboardKey.keyA,
            LogicalKeyboardKey.keyS,
            LogicalKeyboardKey.keyD,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
          };
          if (!wanted.contains(e.logicalKey)) return KeyEventResult.ignored;
          if (e is KeyDownEvent || e is KeyRepeatEvent) {
            _keys.add(e.logicalKey);
          } else if (e is KeyUpEvent) {
            _keys.remove(e.logicalKey);
          }
          return KeyEventResult.handled;
        },
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) {
              _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.12 : 0.89);
              setState(() {});
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              _focus.requestFocus();
              final cell = _cellAt(d.localPosition);
              if (cell != null) widget.onCellTap?.call(cell);
            },
            onScaleStart: (_) => _lastScale = 1,
            onScaleUpdate: (d) {
              _offset -= d.focalPointDelta;
              if (d.pointerCount > 1 && d.scale > 0) {
                _zoomAt(d.localFocalPoint, d.scale / _lastScale);
                _lastScale = d.scale;
              }
              _clamp();
              setState(() {});
            },
            child: Stack(
              children: [
                ClipRect(
                  child: CustomPaint(
                    size: Size(cns.maxWidth, cns.maxHeight),
                    painter: widget.painterBuilder(
                        _tile,
                        -_offset.dx + _shakeAmp * math.sin(_t * 71),
                        -_offset.dy + _shakeAmp * math.cos(_t * 63),
                        // When ambient motion is frozen in the painter, keep
                        // the clock stable so shouldRepaint can skip idle frames.
                        (_tile < 22 && _shakeAmp <= 0) ? 0.0 : _t),
                    foregroundPainter: widget.overlayBuilder?.call(
                        _tile,
                        -_offset.dx + _shakeAmp * math.sin(_t * 71),
                        -_offset.dy + _shakeAmp * math.cos(_t * 63),
                        (_tile < 22 && _shakeAmp <= 0) ? 0.0 : _t),
                  ),
                ),
                // camera controls
                Positioned(
                  right: 8,
                  top: 8,
                  child: Column(children: [
                    _camBtn(Icons.add_rounded,
                        () => _zoomAt(_viewport.center(Offset.zero), 1.25)),
                    const SizedBox(height: 6),
                    _camBtn(Icons.remove_rounded,
                        () => _zoomAt(_viewport.center(Offset.zero), 0.8)),
                    const SizedBox(height: 6),
                    _camBtn(Icons.fit_screen_rounded, () {
                      _zoom = _minZoom;
                      _clamp();
                    }),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _camBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          onTap();
          setState(() {});
        },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, size: 19, color: Colors.white70),
        ),
      );
}
