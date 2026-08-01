import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/league_config.dart';
import '../../core/seeded_rng.dart';
import '../../core/theme.dart';
import '../../models/league.dart';
import '../../providers/war_providers.dart';
import '../../war/war_ai.dart';
import '../../war/war_base.dart';
import '../../war/war_biome.dart';
import '../../war/war_game.dart';
import '../../war/war_player.dart';
import '../../war/war_types.dart';
import 'war_board.dart';
import 'war_board_view.dart';

/// 🧪 The BASE LAB — sandbox for stronghold + terrain generators.
/// Room admins get league presets (size / biome / wards) to preview higher
/// rung enemy maps without climbing the ladder.
class BaseLabScreen extends ConsumerStatefulWidget {
  const BaseLabScreen({super.key});

  @override
  ConsumerState<BaseLabScreen> createState() => _BaseLabScreenState();
}

class _BaseLabScreenState extends ConsumerState<BaseLabScreen> {
  double _difficulty = 60; // 1..100
  double _castles = 4; // 1..6
  double _rivers = 1; // 0..3
  double _lakes = 1; // 0..3
  double _forest = 0.16; // 0..0.35
  double _mountain = 0.11; // 0..0.30
  int _mapSize = Base.defaultSize;
  WarBiome _biome = WarBiome.meadow;
  int? _leaguePreset; // division index, or null = free dials
  // stronghold grammar dials (-1 / null = let the algorithm decide)
  int _archetype = -1; // -1 auto, 0 keep, 1 bailey, 2 twins
  double _gates = 0; // 0 = auto, 1..3 forced
  double _pad = 0; // 0 = auto, 2..5 forced
  double _chamfer = -1; // -1 = auto, 0..3 forced
  double _spacing = 0; // 0 = auto, 2..6 forced
  double _layers = -1; // -1 = auto, 0..8 forced ward partitions
  double _rooms = -1; // -1 = auto, 2..40 forced CITADEL room target
  int _minRooms = 0; // league floor under the citadel plan (0 = none)
  int _innerKeep = -1; // -1 auto, 0 off, 1 on
  int _seed = 1337;
  bool _dials = true; // dials drawer open?

  Base? _base;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final g = ref.read(warGameProvider);
      if (!g.canControlWar) {
        context.go('/war');
        return;
      }
      _generate();
    });
  }

  AiLevel get _ai => _difficulty >= 80
      ? AiLevel.master
      : _difficulty >= 55
          ? AiLevel.elite
          : _difficulty >= 30
              ? AiLevel.seasoned
              : AiLevel.rookie;

  void _applyLeague(int index) {
    final div = LeagueConfig.instance.divisionByIndex(index);
    _leaguePreset = index;
    _mapSize = div.mapSize;
    _biome = WarBiome.of(warBiomeFromString(div.biome));
    _mountain = div.mountainFrac;
    _forest = div.forestFrac;
    // Water weights → forced river/lake dials (preview, not seeded roll).
    if (div.waterWet >= 0.4) {
      _rivers = 2;
      _lakes = 1;
    } else if (div.waterDry >= 0.4) {
      _rivers = 0;
      _lakes = 0;
    } else {
      _rivers = 1;
      _lakes = 1;
    }
    // Match production: wards raise the FLOOR under the citadel plan, they
    // never cap it — the room target itself stays skill/area driven.
    final wards = div.wards;
    _minRooms = wards >= 2 ? 8 + wards * 6 : 0;
    _rooms = -1;
    _layers = -1;
    // Nudge difficulty toward the rung's feel.
    _difficulty = (30 + div.difficulty * 55).clamp(1, 100);
    _generate();
  }

  void _generate({bool reroll = false}) {
    if (reroll) _seed = (_seed * 16807 + 13) & 0x7fffffff;
    final waterMode = _rivers.round() == 0 && _lakes.round() == 0
        ? 0
        : (_rivers.round() + _lakes.round() >= 3 ? 2 : 1);
    final base = Base(
      WarSide.enemy,
      _seed,
      size: _mapSize,
      config: TerrainConfig(
        rivers: _rivers.round(),
        lakes: _lakes.round(),
        forestFrac: _forest,
        mountainFrac: _mountain,
        waterMode: waterMode,
      ),
    );
    // the difficulty dial drives both the WAR CHEST and the plan depth —
    // and the CONTINUOUS skill (past master → citadels), same as a real war
    final s = WarGame.skillFor(_difficulty.round());
    // Same area-scaled war chest the real war hands the enemy, so the
    // preview is honest about how full a big board actually gets.
    final areaMul = (_mapSize * _mapSize) /
        (Base.defaultSize * Base.defaultSize).toDouble();
    final forgeMul = _mapSize >= 60
        ? areaMul * 2.6
        : _mapSize >= 52
            ? areaMul * 1.7
            : areaMul;
    final budget = WarCosts.prepBudgetFor(s) * forgeMul;
    final castleN = _castles.round().clamp(1, 6);
    final crew = [
      for (var i = 0; i < castleN; i++)
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
          minRooms: _minRooms > 1 ? _minRooms : null,
        ));
    setState(() => _base = base);
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(warGameProvider);
    if (!g.canControlWar) {
      return const Scaffold(
        backgroundColor: JarsColors.background,
        body: Center(child: Text('Admin only')),
      );
    }
    final base = _base;
    final divisions = LeagueConfig.instance.divisions;
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
              Flexible(
                child: Text(
                    '${_biome.name} · ${_mapSize}x$_mapSize · seed $_seed · ${AiData.label(_ai)}'
                    '${WarAi.lastBuildStats == null ? '' : ' · ${WarAi.lastBuildStats!.rooms} rooms · ${WarAi.lastBuildStats!.structures} pieces'}',
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                        fontSize: 10, color: JarsColors.textSecondary)),
              ),
              IconButton(
                icon: Icon(_dials ? Icons.tune_rounded : Icons.tune_outlined,
                    color: JarsColors.gold),
                onPressed: () => setState(() => _dials = !_dials),
              ),
            ]),
            Expanded(
              child: base == null
                  ? const Center(
                      child: CircularProgressIndicator(color: JarsColors.gold))
                  : WarBoardView(
                      key: ValueKey('${base.seed}-${base.rows}-${base.hashCode}'),
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
                        biome: _biome,
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('LEAGUE ENEMY PRESET (admin)',
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: JarsColors.textTertiary)),
                    ),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < divisions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            _leagueChip(divisions[i], i),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _dial('DIFFICULTY', _difficulty, 1, 100,
                        '${_difficulty.round()}',
                        (v) {
                      _leaguePreset = null;
                      _difficulty = v;
                    }),
                    _dial('MAP SIZE', _mapSize.toDouble(), 40, 64,
                        '${_mapSize}x$_mapSize', (v) {
                      _leaguePreset = null;
                      _mapSize = v.round();
                      if (_mapSize % 2 != 0) _mapSize += 1;
                    }),
                    _dial('CASTLES', _castles, 1, 6, '${_castles.round()}',
                        (v) => _castles = v),
                    Row(children: [
                      Expanded(
                        child: _dial('RIVERS', _rivers, 0, 3,
                            '${_rivers.round()}', (v) {
                          _leaguePreset = null;
                          _rivers = v;
                        }),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial('LAKES', _lakes, 0, 3, '${_lakes.round()}',
                            (v) {
                          _leaguePreset = null;
                          _lakes = v;
                        }),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _dial('FOREST', _forest, 0, 0.35,
                            '${(_forest * 100).round()}%', (v) {
                          _leaguePreset = null;
                          _forest = v;
                        }),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dial(
                            'MOUNTAINS',
                            _mountain,
                            0,
                            0.30,
                            '${(_mountain * 100).round()}%', (v) {
                          _leaguePreset = null;
                          _mountain = v;
                        }),
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
                    ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leagueChip(LeagueDivision d, int index) {
    final on = _leaguePreset == index;
    return GestureDetector(
      onTap: () => setState(() => _applyLeague(index)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? d.color.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? d.color : JarsColors.border, width: on ? 1.4 : 1),
        ),
        child: Text('${d.icon} ${d.metalName.replaceAll(' League', '')} ${d.mapSize}',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : JarsColors.textSecondary)),
      ),
    );
  }

  Widget _dial(String label, double value, double min, double max, String shown,
      ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
        width: 88,
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: JarsColors.textTertiary)),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: JarsColors.gold,
            inactiveTrackColor: JarsColors.border,
            thumbColor: JarsColors.gold,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (v) => setState(() {
              onChanged(v);
            }),
            onChangeEnd: (_) => _generate(),
          ),
        ),
      ),
      SizedBox(
        width: 52,
        child: Text(shown,
            textAlign: TextAlign.right,
            style: GoogleFonts.spaceMono(
                fontSize: 11, color: JarsColors.textSecondary)),
      ),
    ]);
  }

  Widget _chips(String label, List<String> options, int selected,
      ValueChanged<int> onPick) {
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
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 0; i < options.length; i++)
                GestureDetector(
                  onTap: () => setState(() => onPick(i)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected == i
                          ? JarsColors.gold.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected == i
                              ? JarsColors.gold
                              : JarsColors.border),
                    ),
                    child: Text(options[i],
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: selected == i
                                ? JarsColors.gold
                                : JarsColors.textSecondary)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
