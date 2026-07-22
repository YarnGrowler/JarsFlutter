import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../war/war_engine.dart';
import '../../war/war_types.dart';

/// A live combat effect being animated.
class _Fx {
  final FxEvent e;
  final double duration;
  double age = 0;
  _Fx(this.e, this.duration);
  double get p => (age / duration).clamp(0.0, 1.0);
  bool get dead => age >= duration;
}

/// Turns engine [FxEvent]s into animated battle spectacle: cannonballs arcing,
/// arrows flying, tesla bolts, mine blasts, floating damage numbers, level-up
/// sparkles, and death poofs.
class FxLayer {
  final List<_Fx> _live = [];

  static double _durationFor(FxEvent e) {
    switch (e.kind) {
      case FxKind.shot:
        if (e.defType == DefType.mortar) return 0.95; // long high lob
        return e.defType == DefType.cannon ? 0.7 : 0.35;
      case FxKind.zap:
        return 0.4;
      case FxKind.melee:
        return 0.45;
      case FxKind.trap:
        return 0.55;
      case FxKind.death:
        return 0.85;
      case FxKind.levelup:
        return 0.9;
      case FxKind.heal:
        return 0.7;
    }
  }

  void ingest(List<FxEvent> events) {
    for (final e in events) {
      _live.add(_Fx(e, _durationFor(e)));
      // damage number rider for anything that dealt damage
      if (e.amount > 0) {
        _live.add(_Fx(
            FxEvent(FxKind.melee, e.to,
                amount: -e.amount, bySide: e.bySide), // amount<0 marks "number"
            1.0));
      }
    }
    if (_live.length > 120) _live.removeRange(0, _live.length - 120);
  }

  void tick(double dt) {
    for (final f in _live) {
      f.age += dt;
    }
    _live.removeWhere((f) => f.dead);
  }

  bool get isEmpty => _live.isEmpty;

  CustomPainter painter(double tile, double gx, double gy) =>
      _FxPainter(List.of(_live), tile, gx, gy);
}

class _FxPainter extends CustomPainter {
  final List<_Fx> fx;
  final double tile, gx, gy;
  _FxPainter(this.fx, this.tile, this.gx, this.gy);

  Offset _c(Cell cell) =>
      Offset(gx + (cell.c + 0.5) * tile, gy + (cell.r + 0.5) * tile);

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in fx) {
      final e = f.e;
      // floating damage number (encoded as melee with negative amount)
      if (e.amount < 0) {
        _damageNumber(canvas, f);
        continue;
      }
      switch (e.kind) {
        case FxKind.shot:
          if (e.defType == DefType.mortar) {
            _cannonball(canvas, f, arcScale: 1.7); // only mortars LOB
          } else if (e.defType == DefType.cannon) {
            _cannonShot(canvas, f); // cannons fire FLAT
          } else if (e.defType == DefType.ballista) {
            _dart(canvas, f); // the sniper's bolt
          } else {
            _arrow(canvas, f);
          }
          break;
        case FxKind.zap:
          _bolt(canvas, f);
          break;
        case FxKind.melee:
          _slash(canvas, f);
          break;
        case FxKind.trap:
          _blast(canvas, f);
          break;
        case FxKind.death:
          if (e.defType != null) {
            _collapse(canvas, f); // a building comes down
          } else {
            _fall(canvas, f); // a troop falls
          }
          break;
        case FxKind.levelup:
          _sparkle(canvas, f);
          break;
        case FxKind.heal:
          _heal(canvas, f);
          break;
      }
    }
  }

  void _damageNumber(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to).translate(0, -tile * 0.3 - f.p * tile * 0.7);
    final col = f.e.bySide == WarSide.you ? JarsColors.gold : JarsColors.red;
    final tp = TextPainter(
      text: TextSpan(
          text: '−${-f.e.amount}',
          style: GoogleFonts.spaceGrotesk(
              fontSize: tile * 0.34,
              fontWeight: FontWeight.w800,
              color: col.withValues(alpha: (1 - f.p).clamp(0.0, 1.0)),
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _cannonball(Canvas canvas, _Fx f, {double arcScale = 1.0}) {
    final from = f.e.from ?? f.e.to;
    final a = _c(from), b = _c(f.e.to);
    // LAUNCH: a hard puff and ring at the mortar's mouth
    if (f.p < 0.14) {
      final k = f.p / 0.14;
      canvas.drawCircle(a.translate(0, -tile * 0.15), tile * 0.16 * (1 - k * 0.4),
          Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.85 * (1 - k)));
      canvas.drawCircle(
          a.translate(0, -tile * 0.1),
          tile * (0.1 + 0.35 * k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - k)
            ..color = const Color(0xFF9AA2AE).withValues(alpha: 0.55 * (1 - k)));
    }
    if (f.p < 0.8) {
      final tt = f.p / 0.8;
      final pos = Offset.lerp(a, b, tt)!;
      final arc = math.sin(tt * math.pi) * tile * 0.9 * arcScale;
      // shadow on the ground
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset.lerp(a, b, tt)!, width: tile * 0.2, height: tile * 0.08),
          Paint()..color = Colors.black.withValues(alpha: 0.25));
      // the shell SPINS as it flies
      final shellC = pos.translate(0, -arc);
      canvas.save();
      canvas.translate(shellC.dx, shellC.dy);
      canvas.rotate(tt * 9);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset.zero, width: tile * 0.24, height: tile * 0.2),
          Paint()..color = const Color(0xFF1E242C));
      canvas.drawCircle(Offset(0, -tile * 0.07), tile * 0.035,
          Paint()..color = const Color(0xFFB8543C));
      canvas.restore();
      canvas.drawCircle(shellC.translate(-tile * 0.03, -tile * 0.03),
          tile * 0.04, Paint()..color = Colors.white.withValues(alpha: 0.35));
      // thin smoke trail behind the arc
      final back = Offset.lerp(a, b, (tt - 0.1).clamp(0.0, 1.0))!;
      canvas.drawCircle(
          back.translate(0, -math.sin((tt - 0.1).clamp(0, 1) * math.pi) * tile * 0.9 * arcScale),
          tile * 0.06,
          Paint()..color = const Color(0xFF9AA2AE).withValues(alpha: 0.25));
    } else {
      // impact
      final k = (f.p - 0.8) / 0.2;
      canvas.drawCircle(
          b,
          tile * (0.2 + k * 0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - k)
            ..color = const Color(0xFFFF8A3D).withValues(alpha: 1 - k));
      canvas.drawCircle(b, tile * 0.16 * (1 - k),
          Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.8 * (1 - k)));
    }
  }

  /// Flat cannon shot: muzzle flash, a fast ball on a straight line with a
  /// smoke trail, then the impact burst. No lob — that's the mortar's job.
  void _cannonShot(Canvas canvas, _Fx f) {
    final from = f.e.from ?? f.e.to;
    final a = _c(from), b = _c(f.e.to);
    final dirV = (b - a).distance < 1
        ? const Offset(0, 1)
        : (b - a) / (b - a).distance;
    if (f.p < 0.18) {
      // muzzle BLAST: star flash + directional plume + expanding smoke ring
      final k = f.p / 0.18;
      final m = a + dirV * tile * 0.3;
      canvas.drawCircle(m, tile * 0.2 * (1 - k * 0.5),
          Paint()..color = const Color(0xFFFFF3C0).withValues(alpha: 0.95 * (1 - k)));
      canvas.drawCircle(m + dirV * tile * 0.16 * k, tile * 0.3 * k,
          Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: 0.6 * (1 - k)));
      // flash spikes
      final n = Offset(-dirV.dy, dirV.dx);
      canvas.drawLine(m - n * tile * 0.16 * (1 - k), m + n * tile * 0.16 * (1 - k),
          Paint()
            ..color = const Color(0xFFFFD34D).withValues(alpha: 0.8 * (1 - k))
            ..strokeWidth = 2.5);
      canvas.drawCircle(
          m,
          tile * (0.12 + 0.4 * k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * (1 - k)
            ..color = const Color(0xFF9AA2AE).withValues(alpha: 0.5 * (1 - k)));
    }
    if (f.p < 0.7) {
      final tt = (f.p / 0.7).clamp(0.0, 1.0);
      final pos = Offset.lerp(a, b, tt)!;
      // smoke trail
      for (var i = 1; i <= 3; i++) {
        final back = Offset.lerp(a, b, (tt - i * 0.09).clamp(0.0, 1.0))!;
        canvas.drawCircle(back, tile * (0.05 + i * 0.02),
            Paint()..color = Colors.white.withValues(alpha: 0.16 / i));
      }
      canvas.drawCircle(pos, tile * 0.12, Paint()..color = const Color(0xFF1E242C));
      canvas.drawCircle(pos.translate(-tile * 0.03, -tile * 0.03), tile * 0.035,
          Paint()..color = Colors.white.withValues(alpha: 0.35));
    } else {
      // impact
      final k = (f.p - 0.7) / 0.3;
      canvas.drawCircle(
          b,
          tile * (0.2 + k * 0.45),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - k)
            ..color = const Color(0xFFFF8A3D).withValues(alpha: 1 - k));
      canvas.drawCircle(b, tile * 0.15 * (1 - k),
          Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.8 * (1 - k)));
    }
  }

  /// The ballista bolt: a heavy dart on a flat, FAST line with a shudder on
  /// impact.
  void _dart(Canvas canvas, _Fx f) {
    final from = f.e.from ?? f.e.to;
    final a = _c(from), b = _c(f.e.to);
    final dir = (b - a).distance < 1 ? const Offset(0, 1) : (b - a) / (b - a).distance;
    if (f.p < 0.55) {
      final pos = Offset.lerp(a, b, f.p / 0.55)!;
      final tail = pos - dir * tile * 0.5;
      canvas.drawLine(
          tail,
          pos,
          Paint()
            ..color = const Color(0xFF3A2E1E)
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round);
      final n = Offset(-dir.dy, dir.dx);
      canvas.drawPath(
          Path()
            ..moveTo(pos.dx + dir.dx * 8, pos.dy + dir.dy * 8)
            ..lineTo(pos.dx + n.dx * 5, pos.dy + n.dy * 5)
            ..lineTo(pos.dx - n.dx * 5, pos.dy - n.dy * 5)
            ..close(),
          Paint()..color = const Color(0xFF565E6A));
    } else {
      final k = (f.p - 0.55) / 0.45;
      canvas.drawCircle(
          b,
          tile * (0.12 + k * 0.3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * (1 - k)
            ..color = const Color(0xFFD8C9A3).withValues(alpha: 1 - k));
    }
  }

  /// Healing light: green motes rising, a soft cross at the heart.
  void _heal(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to);
    final fade = (1 - f.p).clamp(0.0, 1.0);
    final green = const Color(0xFF62E88A);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + f.p * 3;
      canvas.drawCircle(
          pos +
              Offset(math.cos(a) * tile * 0.22,
                  math.sin(a) * tile * 0.12 - f.p * tile * 0.4),
          tile * 0.045 * fade,
          Paint()..color = green.withValues(alpha: 0.8 * fade));
    }
    final crossP = Paint()
      ..color = green.withValues(alpha: fade)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final cy = pos.dy - tile * 0.2 - f.p * tile * 0.3;
    canvas.drawLine(Offset(pos.dx - tile * 0.08, cy),
        Offset(pos.dx + tile * 0.08, cy), crossP);
    canvas.drawLine(Offset(pos.dx, cy - tile * 0.08),
        Offset(pos.dx, cy + tile * 0.08), crossP);
  }

  void _arrow(Canvas canvas, _Fx f) {
    final from = f.e.from ?? f.e.to;
    final a = _c(from), b = _c(f.e.to);
    final pos = Offset.lerp(a, b, f.p)!;
    final dir = (b - a).distance < 1 ? const Offset(0, 1) : (b - a) / (b - a).distance;
    final tail = pos - dir * tile * 0.32;
    final paint = Paint()
      ..color = const Color(0xFFD8C9A3)
      ..strokeWidth = 2;
    canvas.drawLine(tail, pos, paint);
    // head
    final n = Offset(-dir.dy, dir.dx);
    canvas.drawPath(
        Path()
          ..moveTo(pos.dx, pos.dy)
          ..lineTo(pos.dx - dir.dx * 6 + n.dx * 3, pos.dy - dir.dy * 6 + n.dy * 3)
          ..lineTo(pos.dx - dir.dx * 6 - n.dx * 3, pos.dy - dir.dy * 6 - n.dy * 3)
          ..close(),
        Paint()..color = const Color(0xFFEEE7D2));
  }

  void _bolt(Canvas canvas, _Fx f) {
    final from = f.e.from ?? f.e.to;
    final a = _c(from), b = _c(f.e.to);
    final alpha = (1 - f.p).clamp(0.0, 1.0);
    final seed = f.e.to.r * 31 + f.e.to.c;
    final path = Path()..moveTo(a.dx, a.dy);
    const segs = 4;
    for (var i = 1; i <= segs; i++) {
      final base = Offset.lerp(a, b, i / segs)!;
      final jag = i == segs
          ? Offset.zero
          : Offset(math.sin(seed + i * 2.3 + f.age * 40) * tile * 0.22,
              math.cos(seed + i * 1.7 + f.age * 35) * tile * 0.14);
      path.lineTo(base.dx + jag.dx, base.dy + jag.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(0xFF57D9FF).withValues(alpha: 0.35 * alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFFB9EFFF).withValues(alpha: alpha));
  }

  void _slash(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to);
    final alpha = (1 - f.p).clamp(0.0, 1.0);
    final sweep = f.p * math.pi * 0.9;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.85 * alpha);
    canvas.drawArc(
        Rect.fromCircle(center: pos, radius: tile * 0.3),
        -math.pi * 0.7 + sweep,
        math.pi * 0.5,
        false,
        paint);
  }

  void _blast(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to);
    final k = f.p;
    // mortar shells blast a whole AREA — ring reaches the splash cells
    final scale = f.e.defType == DefType.mortar ? 1.8 : 1.0;
    canvas.drawCircle(
        pos,
        tile * (0.15 + k * 0.55) * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - k)
          ..color = const Color(0xFFFF8A3D).withValues(alpha: 1 - k));
    canvas.drawCircle(pos, tile * 0.22 * (1 - k) * scale,
        Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 0.7 * (1 - k)));
    if (f.e.defType == DefType.mortar) {
      // scorch flash across the area
      canvas.drawCircle(pos, tile * 1.4 * k,
          Paint()..color = Colors.black.withValues(alpha: 0.12 * (1 - k)));
    }
  }

  /// A troop DIES: tips over rotating and fading, dust bursts at its feet,
  /// and a small spirit wisp drifts skyward.
  void _fall(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to);
    final k = f.p;
    final fade = (1 - k).clamp(0.0, 1.0);
    // dust burst at the feet
    for (var i = 0; i < 5; i++) {
      final a = i * math.pi * 2 / 5;
      final d = tile * 0.32 * k;
      canvas.drawCircle(
          pos + Offset(math.cos(a), math.sin(a) * 0.5) * d,
          tile * 0.06 * fade,
          Paint()..color = const Color(0xFFB9A88C).withValues(alpha: 0.5 * fade));
    }
    // the figure tips sideways and fades
    final emoji = f.e.emoji;
    if (emoji != null && k < 0.75) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate((k / 0.75) * math.pi / 2); // tips a full quarter turn
      final tp = TextPainter(
        text: TextSpan(
            text: emoji,
            style: TextStyle(
                fontSize: tile * 0.42,
                color: Colors.white.withValues(alpha: fade))),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.saveLayer(
          Rect.fromCircle(center: Offset.zero, radius: tile * 0.5),
          Paint()..color = Colors.white.withValues(alpha: fade));
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      canvas.restore();
    }
    // the spirit drifts up
    final wispY = pos.dy - tile * (0.2 + k * 0.9);
    canvas.drawCircle(
        Offset(pos.dx + math.sin(k * 9) * tile * 0.06, wispY),
        tile * 0.07 * fade,
        Paint()..color = Colors.white.withValues(alpha: 0.55 * fade));
    canvas.drawCircle(
        Offset(pos.dx + math.sin(k * 9) * tile * 0.06, wispY + tile * 0.08),
        tile * 0.045 * fade,
        Paint()..color = Colors.white.withValues(alpha: 0.3 * fade));
  }

  /// A building COLLAPSES: stone chunks fly on small arcs, smoke columns up.
  void _collapse(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to);
    final k = f.p;
    final fade = (1 - k).clamp(0.0, 1.0);
    final seed = f.e.to.r * 17 + f.e.to.c * 31;
    for (var i = 0; i < 5; i++) {
      final a = (seed + i * 2.1) % (math.pi * 2);
      final reach = tile * (0.25 + (i % 3) * 0.15) * k;
      final chunk = pos +
          Offset(math.cos(a) * reach,
              math.sin(a) * reach * 0.6 - math.sin(k * math.pi) * tile * 0.35);
      canvas.save();
      canvas.translate(chunk.dx, chunk.dy);
      canvas.rotate(a + k * 5);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: tile * 0.1, height: tile * 0.08),
          Paint()..color = const Color(0xFF565E6A).withValues(alpha: fade));
      canvas.restore();
    }
    // smoke column
    for (var i = 0; i < 3; i++) {
      final rise = k * tile * (0.5 + i * 0.25);
      canvas.drawCircle(
          Offset(pos.dx + math.sin(k * 4 + i * 2) * tile * 0.08, pos.dy - rise),
          tile * (0.12 + k * 0.1) * (1 - i * 0.2),
          Paint()
            ..color = const Color(0xFF6B7482).withValues(alpha: 0.4 * fade));
    }
    // ground flash
    if (k < 0.3) {
      canvas.drawCircle(pos, tile * (0.2 + k),
          Paint()..color = const Color(0xFFFF8A3D).withValues(alpha: 0.5 * (1 - k / 0.3)));
    }
  }

  void _sparkle(Canvas canvas, _Fx f) {
    final pos = _c(f.e.to).translate(0, -tile * 0.4 - f.p * tile * 0.4);
    final alpha = (1 - f.p).clamp(0.0, 1.0);
    final paint = Paint()..color = JarsColors.gold.withValues(alpha: alpha);
    for (var i = 0; i < 3; i++) {
      final off = Offset(
          math.sin(i * 2.1 + f.age * 8) * tile * 0.2, -i * tile * 0.12);
      final c = pos + off;
      final s = tile * 0.06;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - s)
            ..lineTo(c.dx + s * 0.4, c.dy)
            ..lineTo(c.dx, c.dy + s)
            ..lineTo(c.dx - s * 0.4, c.dy)
            ..close(),
          paint);
    }
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}
