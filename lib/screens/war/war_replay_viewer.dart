import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/low_performance_mode_provider.dart';
import '../../war/war_base.dart';
import '../../war/war_biome.dart';
import '../../war/war_engine.dart';
import '../../war/war_types.dart';
import 'battle_fx.dart';
import 'war_board.dart';
import 'war_board_view.dart';

/// One raid in a playback playlist (the WAR CHRONICLE strings many together).
class ReplayEntry {
  final Base base;
  final List<RaidFrame> frames;
  final String title;
  final String? summary; // '⚔ sent · 💀 lost · ⏱ length' — shown under the title
  final Set<int>? fog; // null = no fog
  final WarBiome biome;
  const ReplayEntry(
      {required this.base,
      required this.frames,
      required this.title,
      this.fog,
      this.summary,
      this.biome = WarBiome.meadow});
}

/// Full-screen CoC-style battle replay: play/pause + frame scrubbing over the
/// real board, with the recorded combat FX (arrows, cannonballs, tesla bolts),
/// 1×/2×/4× speed, smooth glide between frames. Pan & zoom still work while
/// you watch. Give it several [ReplayEntry]s and it plays them back to back —
/// the full story of the war.
class WarReplayViewer extends StatefulWidget {
  final List<ReplayEntry> entries;
  const WarReplayViewer({super.key, required this.entries});

  /// Convenience: open the viewer as a full-screen dialog for ONE raid.
  static void show(BuildContext context,
      {required Base base,
      required List<RaidFrame> frames,
      required String title,
      Set<int>? fog,
      String? summary,
      WarBiome biome = WarBiome.meadow}) {
    showChronicle(context, entries: [
      ReplayEntry(
          base: base,
          frames: frames,
          title: title,
          fog: fog,
          summary: summary,
          biome: biome)
    ]);
  }

  /// Open a multi-raid playback (e.g. every raid of the war, in order).
  static void showChronicle(BuildContext context,
      {required List<ReplayEntry> entries}) {
    if (entries.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dCtx) => Dialog.fullscreen(
        backgroundColor: const Color(0xFF090B12),
        child: WarReplayViewer(entries: entries),
      ),
    );
  }

  @override
  State<WarReplayViewer> createState() => _WarReplayViewerState();
}

class _WarReplayViewerState extends State<WarReplayViewer> {
  int _entry = 0;
  int _frame = 0;
  bool _playing = true;
  int _speed = 1; // 1× / 2× / 4× / 8×
  double _acc = 0; // progress toward the next frame (drives the glide)
  FxLayer _fx = FxLayer();
  final WarBoardController _cam = WarBoardController();

  void _ingest(List<FxEvent> evs) {
    for (final e in evs) {
      // only the IMPACT rattles the room — launches don't, and gently
      if (e.defType == DefType.mortar && e.kind == FxKind.trap) {
        _cam.kick(5);
      }
    }
    _fx.ingest(evs);
  }

  static const double _period = 0.55; // seconds per frame at 1×
  static const double _interlude = 1.4; // pause between chronicle raids

  ReplayEntry get _cur => widget.entries[_entry];
  List<RaidFrame> get _frames => _cur.frames;

  @override
  void initState() {
    super.initState();
    if (_frames.isNotEmpty) _ingest(_frames.first.fx);
  }

  void _jumpEntry(int e) {
    _entry = e.clamp(0, widget.entries.length - 1);
    _frame = 0;
    _acc = 0;
    _fx = FxLayer();
    if (_frames.isNotEmpty) _ingest(_frames.first.fx);
  }

  /// Driven by the board's ticker — buttery playback, no Timer chunkiness.
  void _onTick(double dt) {
    _fx.tick(dt * _speed);
    if (!_playing) return;
    _acc += dt * _speed;
    var advanced = false;
    while (_acc >= _period) {
      if (_frame >= _frames.length - 1) {
        if (_entry < widget.entries.length - 1) {
          // roll into the next raid of the chronicle after a beat
          if (_acc >= _period + _interlude) {
            _jumpEntry(_entry + 1);
            advanced = true;
            continue;
          }
        } else {
          _acc = _period; // hold the final frame fully blended
          _playing = false;
          advanced = true;
        }
        break;
      }
      _acc -= _period;
      _frame++;
      _ingest(_frames[_frame].fx);
      advanced = true;
    }
    if (advanced && mounted) setState(() {});
  }

  double get _blend => _playing ? (_acc / _period).clamp(0.0, 1.0) : 1.0;

  @override
  Widget build(BuildContext context) {
    final many = widget.entries.length > 1;
    return SafeArea(
      child: Column(
        children: [
          Row(children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_cur.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: JarsColors.textPrimary)),
                  if (_cur.summary != null)
                    Text(_cur.summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceMono(
                            fontSize: 9.5, color: JarsColors.gold)),
                ],
              ),
            ),
            if (many)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('raid ${_entry + 1}/${widget.entries.length}',
                    style: GoogleFonts.spaceMono(
                        fontSize: 12, color: JarsColors.gold)),
              ),
            Text('${_frame + 1}/${_frames.length}',
                style: GoogleFonts.spaceMono(
                    fontSize: 12, color: JarsColors.textSecondary)),
            const SizedBox(width: 12),
          ]),
          Expanded(
            child: Consumer(builder: (context, ref, _) {
              final lowPerf = ref.watch(lowPerformanceModeProvider);
              return WarBoardView(
                key: ValueKey(_entry), // new raid → fresh camera fit
                base: _cur.base,
                controller: _cam,
                startFitted: true,
                onTick: _onTick,
                lowPerformanceMode: lowPerf,
                painterBuilder: (tile, gx, gy, t) => WarBoardPainter(
                  base: _cur.base,
                  tile: tile,
                  gx: gx,
                  gy: gy,
                  t: t,
                  ownBase: true,
                  fog: _cur.fog,
                  replayFrame: _frames[_frame.clamp(0, _frames.length - 1)],
                  replayPrev: _frame > 0 ? _frames[_frame - 1] : null,
                  replayBlend: _blend,
                  biome: _cur.biome,
                  lowPerformanceMode: lowPerf,
                ),
                overlayBuilder: (tile, gx, gy, t) => (lowPerf || _fx.isEmpty)
                    ? null
                    : _fx.painter(tile, gx, gy),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              if (many)
                IconButton(
                  icon: const Icon(Icons.fast_rewind_rounded,
                      color: Colors.white70),
                  onPressed: () => setState(() => _jumpEntry(_entry - 1)),
                ),
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70),
                onPressed: () => setState(() {
                  _frame = (_frame - 1).clamp(0, _frames.length - 1);
                  _playing = false;
                }),
              ),
              IconButton(
                icon: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: JarsColors.gold,
                    size: 32),
                onPressed: () => setState(() {
                  if (!_playing &&
                      _frame >= _frames.length - 1 &&
                      _entry >= widget.entries.length - 1) {
                    _jumpEntry(0);
                  }
                  _playing = !_playing;
                }),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white70),
                onPressed: () => setState(() {
                  _frame = (_frame + 1).clamp(0, _frames.length - 1);
                  _playing = false;
                }),
              ),
              if (many)
                IconButton(
                  icon: const Icon(Icons.fast_forward_rounded,
                      color: Colors.white70),
                  onPressed: () => setState(() => _jumpEntry(_entry + 1)),
                ),
              GestureDetector(
                onTap: () => setState(() => _speed =
                    _speed == 1 ? 2 : (_speed == 2 ? 4 : (_speed == 4 ? 8 : 1))),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: JarsColors.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(
                        color: JarsColors.gold.withValues(alpha: 0.5)),
                  ),
                  child: Text('$_speed×',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: JarsColors.textPrimary)),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _frame
                      .toDouble()
                      .clamp(0, (_frames.length - 1).toDouble()),
                  min: 0,
                  max: (_frames.length - 1).toDouble().clamp(1, 9999),
                  activeColor: JarsColors.gold,
                  inactiveColor: JarsColors.border,
                  onChanged: (v) => setState(() {
                    _frame = v.round();
                    _playing = false;
                  }),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
