import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/seeded_rng.dart';
import '../../core/theme.dart';
import '../../war/war_ai.dart';
import '../../war/war_base.dart';
import '../../war/war_biome.dart';
import '../../war/war_game.dart';
import '../../war/war_player.dart';
import '../../war/war_types.dart';
import 'war_board.dart';
import 'war_board_view.dart';

/// 🧪 The BASE LAB — a sandbox for the stronghold + terrain generators.
/// Turn the dials (difficulty 1–100, castles, rivers, lakes, forest,
/// mountains), hit GENERATE, and see what the algorithm dreams up.
class BaseLabScreen extends StatefulWidget {
  const BaseLabScreen({super.key});

  @override
  State<BaseLabScreen> createState() => _BaseLabScreenState();
}

class _BaseLabScreenState extends State<BaseLabScreen> {
  double _difficulty = 60; // 1..100
  double _castles = 4; // 1..6
  double _rivers = 1; // 0..3
  double _lakes = 1; // 0..3
  double _forest = 0.16; // 0..0.35
  double _mountain = 0.11; // 0..0.30
  // stronghold grammar dials (-1 / null = let the algorithm decide)
  int _archetype = -1; // -1 auto, 0 keep, 1 bailey, 2 twins
  double _gates = 0; // 0 = auto, 1..3 forced
  double _pad = 0; // 0 = auto, 2..5 forced
  double _chamfer = -1; // -1 = auto, 0..3 forced
  double _spacing = 0; // 0 = auto, 2..6 forced
  double _layers = -1; // -1 = auto, 0..8 forced ward partitions
  double _rooms = -1; // -1 = auto, 2..40 forced CITADEL room target
  int _innerKeep = -1; // -1 auto, 0 off, 1 on
  int _seed = 1337;
  bool _dials = true; // dials drawer open?

  Base? _base;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  AiLevel get _ai => _difficulty >= 80
      ? AiLevel.master
      : _difficulty >= 55
          ? AiLevel.elite
          : _difficulty >= 30
              ? AiLevel.seasoned
              : AiLevel.rookie;

  void _generate({bool reroll = false}) {
    if (reroll) _seed = (_seed * 16807 + 13) & 0x7fffffff;
    final base = Base(WarSide.enemy, _seed,
        config: TerrainConfig(
          rivers: _rivers.round(),
          lakes: _lakes.round(),
          forestFrac: _forest,
          mountainFrac: _mountain,
        ));
    // the difficulty dial drives both the WAR CHEST and the plan depth —
    // and the CONTINUOUS skill (past master → citadels), same as a real war
    final s = WarGame.skillFor(_difficulty.round());
    final budget = WarCosts.prepBudgetFor(s);
    final crew = [
      for (var i = 0; i < _castles.round(); i++)
        WarPlayer(
            id: 'lab$i',
            name: 'Lab $i',
            emoji: '🧪',
            colorValue: 0xFFE6483F,
            side: WarSide.enemy,
            ai: _ai,
            resources: budget)
          ..skillMul = s / AiData.skill(_ai)
    ];
    WarAi.designBase(
        base, crew, SeededRng(seedFromParts([_seed, 'lab', _difficulty.round()])),
        style: StrongholdStyle(
          archetype: _archetype < 0 ? null : _archetype,
          gates: _gates.round() == 0 ? null : _gates.round(),
          pad: _pad.round() == 0 ? null : _pad.round(),
          chamfer: _chamfer.round() < 0 ? null : _chamfer.round(),
          towerSpacing: _spacing.round() == 0 ? null : _spacing.round(),
          innerKeep: _innerKeep < 0 ? null : _innerKeep == 1,
          layers: _layers.round() < 0 ? null : _layers.round(),
          rooms: _rooms.round() < 0 ? null : _rooms.round().clamp(2, 40),
        ));
    setState(() => _base = base);
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                onPressed: () => context.go('/war'),
              ),
              Text('🧪 BASE LAB',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: JarsColors.textPrimary)),
              const Spacer(),
              Text(
                  'seed $_seed · ${AiData.label(_ai)}'
                  '${WarAi.lastBuildStats == null ? '' : ' · ${WarAi.lastBuildStats!.rooms} rooms · ${WarAi.lastBuildStats!.structures} pieces'}'
                  '${_archetype < 0 ? '' : ' · ${const ['Keep', 'Bailey', 'Twins'][_archetype]}'}'
                  '${_layers.round() < 0 ? '' : ' · ${_layers.round()} wards'}',
                  style: GoogleFonts.spaceMono(
                      fontSize: 11, color: JarsColors.textSecondary)),
              IconButton(
                icon: Icon(_dials ? Icons.tune_rounded : Icons.tune_outlined,
                    color: JarsColors.gold),
                onPressed: () => setState(() => _dials = !_dials),
              ),
            ]),
            Expanded(
              child: base == null
                  ? const SizedBox.shrink()
                  : WarBoardView(
                      key: ValueKey('${base.seed}-${base.hashCode}'),
                      base: base,
                      startFitted: true,
                      painterBuilder: (tile, gx, gy, t) => WarBoardPainter(
                        base: base,
                        tile: tile,
                        gx: gx,
                        gy: gy,
                        t: t,
                        ownBase: true, // show the hidden pieces too
                        showTerritory: false,
                        biome: WarBiome.meadow,
                      ),
                    ),
            ),
            if (_dials)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF10131C),
                  border: Border(top: BorderSide(color: JarsColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dial('DIFFICULTY', _difficulty, 1, 100,
                        '${_difficulty.round()}',
                        (v) => _difficulty = v),
                    _dial('CASTLES', _castles, 1, 6, '${_castles.round()}',
                        (v) => _castles = v),
                    Row(children: [
                      Expanded(
                        child: _dial('RIVERS', _rivers, 0, 3,
                            '${_rivers.round()}', (v) => _rivers = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial('LAKES', _lakes, 0, 3, '${_lakes.round()}',
                            (v) => _lakes = v),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial('FOREST', _forest, 0, 0.35,
                            '${(_forest * 100).round()}%', (v) => _forest = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'MOUNTAINS',
                            _mountain,
                            0,
                            0.30,
                            '${(_mountain * 100).round()}%',
                            (v) => _mountain = v),
                      ),
                    ]),
                    // ── stronghold grammar dials ──
                    Row(children: [
                      Expanded(
                        child: _dial('GATES', _gates, 0, 3,
                            _gates.round() == 0 ? 'auto' : '${_gates.round()}',
                            (v) => _gates = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial('PADDING', _pad, 0, 14,
                            _pad.round() == 0 ? 'auto' : '${_pad.round()}',
                            (v) => _pad = v < 2 && v > 0 ? 2 : v),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial(
                            'CORNER CUT',
                            _chamfer,
                            -1,
                            3,
                            _chamfer.round() < 0 ? 'auto' : '${_chamfer.round()}',
                            (v) => _chamfer = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'TOWER GAP',
                            _spacing,
                            0,
                            6,
                            _spacing.round() == 0 ? 'auto' : '${_spacing.round()}',
                            (v) => _spacing = v < 2 && v > 0 ? 2 : v),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial(
                            'WARD LAYERS',
                            _layers,
                            -1,
                            8,
                            _layers.round() < 0 ? 'auto' : '${_layers.round()}',
                            (v) => _layers = v),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'ROOMS',
                            _rooms,
                            -1,
                            40,
                            _rooms.round() < 0 ? 'auto' : '${_rooms.round()}',
                            (v) => _rooms = v),
                      ),
                    ]),
                    Row(children: [
                      _chips('SHAPE', const ['AUTO', 'KEEP', 'BAILEY', 'TWINS'],
                          _archetype + 1, (i) {
                        _archetype = i - 1;
                        _generate();
                      }),
                      const SizedBox(width: 12),
                      _chips('INNER KEEP', const ['AUTO', 'OFF', 'ON'],
                          _innerKeep + 1, (i) {
                        _innerKeep = i - 1;
                        _generate();
                      }),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _generate(reroll: true),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: JarsColors.gold,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('🎲 GENERATE',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _generate(),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: JarsColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: JarsColors.border),
                          ),
                          child: Text('↻ SAME SEED',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: JarsColors.textPrimary)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A row of exclusive choice chips (SHAPE, INNER KEEP…).
  Widget _chips(
      String label, List<String> options, int selected, void Function(int) onPick) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: JarsColors.textTertiary)),
          const SizedBox(height: 3),
          Wrap(
            spacing: 4,
            children: [
              for (var i = 0; i < options.length; i++)
                GestureDetector(
                  onTap: () => setState(() => onPick(i)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: i == selected
                          ? JarsColors.gold.withValues(alpha: 0.2)
                          : JarsColors.surface,
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(
                          color: i == selected
                              ? JarsColors.gold
                              : JarsColors.border),
                    ),
                    child: Text(options[i],
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: JarsColors.textPrimary)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dial(String label, double value, double min, double max,
      String readout, void Function(double) set) {
    return Row(children: [
      SizedBox(
        width: 82,
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: JarsColors.textTertiary)),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: JarsColors.gold,
            inactiveColor: JarsColors.border,
            onChanged: (v) => setState(() => set(v)),
            onChangeEnd: (_) => _generate(),
          ),
        ),
      ),
      SizedBox(
        width: 36,
        child: Text(readout,
            textAlign: TextAlign.right,
            style: GoogleFonts.spaceMono(
                fontSize: 11, color: JarsColors.textSecondary)),
      ),
    ]);
  }
}
