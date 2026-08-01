import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';
import '../../war/war_base.dart';
import '../../war/war_engine.dart' show AttackState;
import '../../war/war_types.dart';
import 'war_board.dart';
import 'war_board_view.dart';
import 'war_info_cards.dart';

/// Prep-day base editor. Arm a tool, tap ground to place; tap a placed defense
/// to SELECT it (range ring + info, and SELL if it's yours); 🪓 clears forests
/// for ⚡.
class BaseBuilderScreen extends ConsumerStatefulWidget {
  const BaseBuilderScreen({super.key});

  @override
  ConsumerState<BaseBuilderScreen> createState() => _BaseBuilderScreenState();
}

class _BaseBuilderScreenState extends ConsumerState<BaseBuilderScreen> {
  bool _castleTool = true;
  bool _clearTool = false;
  DefType? _defTool;
  Cell? _selectedCell; // a placed structure being inspected

  @override
  Widget build(BuildContext context) {
    // a direct deep-link/reload can land here WITHOUT ever passing through
    // the war hub — the roster/remote-state sync has to fire from every
    // war screen, not just the hub, or this screen could show a stale or
    // wrong-identity roster.
    ref.watch(warRoomSyncProvider);
    final g = ref.watch(warGameProvider);
    final base = g.youBase;

    // No blanket "buildable" outlines — they turned the map into a chip grid.
    // Only the 🪓 Clear tool highlights its valid targets (forests).
    final buildable = <int>{};
    if (_clearTool) {
      for (var r = 0; r < Base.rows; r++) {
        for (var c = 0; c < Base.cols; c++) {
          if (base.isInterior(r, c) && base.grid[r][c].terrain == Terrain.forest) {
            buildable.add(r * Base.cols + c);
          }
        }
      }
    }

    // CoC-style radius preview for the selected defense (+ blind spot)
    final rings = <(Cell, double, double)>[];
    final sel = _selectedCell;
    final selStruct = sel == null ? null : base.structAt(sel.r, sel.c);
    if (sel != null && selStruct != null) {
      var radius = selStruct.spec.isShooter
          ? selStruct.spec.range.toDouble()
          : (selStruct.type == DefType.guardPost
              // upgraded pavilions patrol +2 per level
              ? (AttackState.garrisonLeash + (selStruct.level - 1) * 2)
                  .toDouble()
              : 0.0);
      // towers on HILLS see one tile farther
      if (selStruct.spec.isShooter &&
          base.grid[sel.r][sel.c].terrain == Terrain.hill) {
        radius += 1;
      }
      if (radius > 0) {
        rings.add((sel, radius, selStruct.spec.minRange.toDouble()));
      }
    }

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(context, g),
            Expanded(
              child: WarBoardView(
                base: base,
                startFitted: true,
                onCellTap: (cell) => _onTap(cell, g),
                painterBuilder: (tile, gx, gy, t) => WarBoardPainter(
                  base: base,
                  tile: tile,
                  gx: gx,
                  gy: gy,
                  t: t,
                  ownBase: true,
                  buildable: buildable,
                  rangeRings: rings,
                  selected: _selectedCell,
                ),
              ),
            ),
            if (selStruct != null) _inspectPanel(g, sel!, selStruct),
            _palette(g),
          ],
        ),
      ),
    );
  }

  /// ⧉ Export: the whole build as a copyable code.
  void _shareCode(BuildContext context, dynamic g) {
    final code = g.exportBaseCode() as String;
    Clipboard.setData(ClipboardData(text: code));
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text('⧉ BASE CODE',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: JarsColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Copied to your clipboard. Paste it into ⇩ IMPORT in any '
                'version to rebuild this exact fortress — terrain and all.',
                style: GoogleFonts.inter(
                    fontSize: 12, color: JarsColors.textSecondary)),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JarsColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JarsColors.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(code,
                    style: GoogleFonts.spaceMono(
                        fontSize: 9, color: JarsColors.textTertiary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx), child: const Text('DONE')),
        ],
      ),
    );
  }

  /// ⇩ Import: paste a code, get that fortress.
  void _importCode(BuildContext context, dynamic g) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text('⇩ IMPORT BASE CODE',
            style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: JarsColors.textPrimary)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          style: GoogleFonts.spaceMono(fontSize: 10, color: JarsColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'JARS1.…',
            hintStyle: GoogleFonts.spaceMono(
                fontSize: 10, color: JarsColors.textTertiary),
            filled: true,
            fillColor: JarsColors.background,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: JarsColors.border)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx), child: const Text('CANCEL')),
          FilledButton(
            onPressed: () {
              final err = g.importBaseCode(ctrl.text) as String?;
              Navigator.pop(dCtx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(err ?? '🏰 Fortress restored — welcome home.')));
              if (err == null) setState(() => _selectedCell = null);
            },
            child: const Text('IMPORT'),
          ),
        ],
      ),
    );
  }

  void _onTap(Cell cell, dynamic g) {
    final base = g.youBase as Base;
    final s = base.structAt(cell.r, cell.c);

    // 🪓 clear tool
    if (_clearTool) {
      final err = g.clearForestAt(cell.r, cell.c) as String?;
      _feedback(err);
      setState(() {});
      return;
    }
    // tap ANY crew piece → inspect (range ring + info) — the whole base
    // belongs to the whole crew, but selling is owner-only.
    if (s != null && !s.isCastle) {
      setState(() => _selectedCell = cell);
      HapticFeedback.selectionClick();
      return;
    }
    if (s != null && s.isCastle) {
      setState(() => _selectedCell = cell);
      return;
    }
    // place with the armed tool
    if (_castleTool) {
      final err = g.placeCastle(cell.r, cell.c) as String?;
      _feedback(err);
      if (err == null) setState(() => _selectedCell = cell);
    } else if (_defTool != null) {
      final err = g.placeStructure(cell.r, cell.c, _defTool) as String?;
      _feedback(err);
      if (err == null) {
        // auto-select so the new piece's range ring shows immediately
        setState(() => _selectedCell = cell);
      }
    } else {
      setState(() => _selectedCell = null);
    }
  }

  void _feedback(String? err) {
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else {
      HapticFeedback.selectionClick();
    }
  }

  Widget _topBar(BuildContext context, dynamic g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            onPressed: () => context.go('/war'),
          ),
          Text(g.active.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUILD · ${g.active.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: JarsColors.textPrimary)),
                Text(
                    g.activeHasCastle
                        ? 'tap a placed defense to see its range'
                        : 'place your 🏰 castle first',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        color: g.activeHasCastle
                            ? JarsColors.textTertiary
                            : JarsColors.gold)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _shareCode(context, g),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('⧉',
                  style: GoogleFonts.inter(
                      fontSize: 17, color: JarsColors.textSecondary)),
            ),
          ),
          GestureDetector(
            onTap: () => _importCode(context, g),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('⇩',
                  style: GoogleFonts.inter(
                      fontSize: 17, color: JarsColors.textSecondary)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: JarsColors.gold.withValues(alpha: 0.5)),
            ),
            child: Text('⚡ ${g.active.resources.round()}',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              g.readyUp();
              context.go('/war');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: JarsColors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JarsColors.green),
              ),
              child: Text('DONE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }

  /// The inspect panel for a selected placed defense (range + info, plus sell
  /// when the piece is yours).
  Widget _inspectPanel(dynamic g, Cell cell, dynamic s) {
    final spec = s.spec as DefSpec;
    final canSell = g.canRemoveStructure(cell.r, cell.c) as bool;
    final mine = (s.ownerId as String) == g.active.id;
    final ownerName = g.structureOwnerName(cell.r, cell.c) as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF10131C),
        border: Border(top: BorderSide(color: JarsColors.border)),
      ),
      child: Row(children: [
        Text(spec.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(spec.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: JarsColors.textPrimary)),
                ),
                if ((s.level as int) >= 2)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: JarsColors.gold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: JarsColors.gold.withValues(alpha: 0.6)),
                      ),
                      child: Text('LVL ${s.level}',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: JarsColors.gold)),
                    ),
                  ),
              ]),
              if (!mine)
                Text(
                    ownerName != null
                        ? 'belongs to $ownerName'
                        : 'belongs to a departed crewmate',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: JarsColors.gold)),
              Text(
                  '❤ ${s.hp}/${s.maxHp}'
                  '${spec.isShooter ? ' · ⚔ ${s.damage} · 🎯 ${spec.range}' : ''}'
                  '${spec.type == DefType.guardPost ? ' · 📍 patrol ${AttackState.garrisonLeash + ((s.level as int) - 1) * 2}' : ''}'
                  '${spec.type == DefType.housing ? ' · 🏠 tents +1 defender' : ''}'
                  '${g.youBase.grid[cell.r][cell.c].terrain == Terrain.hill && spec.isShooter ? ' · ⛰ high ground +1🎯' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                      fontSize: 10.5, color: JarsColors.textSecondary)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => showDefenseCard(context, spec.type,
              level: s.level as int),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('ⓘ',
                style:
                    GoogleFonts.inter(fontSize: 16, color: JarsColors.textTertiary)),
          ),
        ),
        if (spec.upgradeCost > 0 && (s.level as int) < spec.maxLevel) ...[
          GestureDetector(
            onTap: () {
              final err = g.upgradeStructure(cell.r, cell.c) as String?;
              if (err != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(err)));
              } else {
                HapticFeedback.selectionClick();
                setState(() {});
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: JarsColors.gold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
                border:
                    Border.all(color: JarsColors.gold.withValues(alpha: 0.6)),
              ),
              child: Text(
                  'LVL ${(s.level as int) + 1} ⚡${spec.upgradeCost * (s.level as int)}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (canSell)
          GestureDetector(
            onTap: () {
              final err = g.removeStructure(cell.r, cell.c) as String?;
              _feedback(err);
              if (err == null) setState(() => _selectedCell = null);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: JarsColors.red.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: JarsColors.red.withValues(alpha: 0.6)),
              ),
              child: Text('SELL +⚡${spec.cost}',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: JarsColors.textPrimary)),
            ),
          ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => _selectedCell = null),
          child: const Icon(Icons.close_rounded,
              size: 18, color: JarsColors.textTertiary),
        ),
      ]),
    );
  }

  Widget _palette(dynamic g) {
    Widget chip({
      required String emoji,
      required String name,
      required int cost,
      required bool selected,
      required VoidCallback onTap,
      VoidCallback? onInfo,
    }) {
      final affordable = cost <= g.active.resources || selected;
      return Opacity(
        opacity: affordable ? 1 : 0.5,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onInfo,
          child: Container(
            width: 78,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: selected
                  ? JarsColors.primary.withValues(alpha: 0.2)
                  : JarsColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected ? JarsColors.primary : JarsColors.border,
                  width: selected ? 2 : 1),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Column(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 2),
                    Text(name,
                        style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textSecondary)),
                    Text(cost == 0 ? 'free' : '⚡$cost',
                        style: GoogleFonts.spaceMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.gold)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C14),
        border: Border(top: BorderSide(color: JarsColors.border)),
      ),
      child: SizedBox(
        height: 78,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            chip(
              emoji: '🏰',
              name: 'Castle',
              cost: 0,
              selected: _castleTool,
              onTap: () => setState(() {
                _castleTool = true;
                _clearTool = false;
                _defTool = null;
              }),
              onInfo: () => showDefenseCard(context, DefType.castle),
            ),
            for (final type in kBuildPalette)
              chip(
                emoji: kDefSpecs[type]!.emoji,
                name: kDefSpecs[type]!.name,
                cost: kDefSpecs[type]!.cost,
                selected: _defTool == type,
                onTap: () => setState(() {
                  _castleTool = false;
                  _clearTool = false;
                  _defTool = type;
                }),
                onInfo: () => showDefenseCard(context, type),
              ),
            chip(
              emoji: '🪓',
              name: 'Clear',
              cost: WarCosts.clearForest.round(),
              selected: _clearTool,
              onTap: () => setState(() {
                _castleTool = false;
                _clearTool = true;
                _defTool = null;
              }),
            ),
          ],
        ),
      ),
    );
  }
}
