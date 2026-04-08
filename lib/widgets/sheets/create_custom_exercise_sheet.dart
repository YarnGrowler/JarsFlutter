import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/count_unit.dart';
import '../../core/theme.dart';
import '../../providers/exercise_provider.dart';
import '../../services/exercise_service.dart';

/// Bottom sheet: create a room custom exercise with reps/time, scoring mode, timer, and weight bonuses.
class CreateCustomExerciseSheet extends ConsumerStatefulWidget {
  final String roomId;

  const CreateCustomExerciseSheet({super.key, required this.roomId});

  @override
  ConsumerState<CreateCustomExerciseSheet> createState() =>
      _CreateCustomExerciseSheetState();
}

class _CreateCustomExerciseSheetState
    extends ConsumerState<CreateCustomExerciseSheet> {
  late final TextEditingController _name;
  late final TextEditingController _points;
  late final TextEditingController _icon;
  late final TextEditingController _weightThreshold;
  late final TextEditingController _weightMultiplier;

  CountUnit _unit = CountUnit.reps;
  TimePointsMode _timePointsMode = TimePointsMode.perMinute;
  bool _timerUi = false;
  bool _supportsWeight = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _points = TextEditingController();
    _icon = TextEditingController(text: '💪');
    _weightThreshold = TextEditingController();
    _weightMultiplier = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _name.dispose();
    _points.dispose();
    _icon.dispose();
    _weightThreshold.dispose();
    _weightMultiplier.dispose();
    super.dispose();
  }

  String get _pointsLabel {
    switch (_unit) {
      case CountUnit.reps:
        return 'Points per rep';
      case CountUnit.seconds:
        return _timePointsMode == TimePointsMode.perSecond
            ? 'Points per second'
            : 'Points per minute of time';
      case CountUnit.minutes:
        return 'Points per minute';
    }
  }

  String? get _pointsHelper {
    switch (_unit) {
      case CountUnit.reps:
        return 'Each rep is multiplied by this value.';
      case CountUnit.seconds:
        return _timePointsMode == TimePointsMode.perSecond
            ? 'Total seconds × this rate.'
            : 'Elapsed time is converted to minutes; points use that rate.';
      case CountUnit.minutes:
        return 'Whole minutes × this rate.';
    }
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final points = double.tryParse(_points.text);
    if (name.isEmpty || points == null || points < 0) return;

    double? wTh;
    double? wMul;
    if (_supportsWeight) {
      wTh = double.tryParse(_weightThreshold.text);
      if (wTh == null || wTh <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a weight threshold greater than 0.')),
        );
        return;
      }
      final mulRaw = _weightMultiplier.text.trim();
      wMul = mulRaw.isEmpty ? 1.0 : double.tryParse(mulRaw);
      if (wMul == null || wMul < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bonus multiplier must be a valid number.')),
        );
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      await ExerciseService.createCustomExercise(
        roomId: widget.roomId,
        name: name,
        points: points,
        icon: _icon.text.trim().isEmpty ? '💪' : _icon.text.trim(),
        category: 'Custom',
        countUnit: _unit,
        timePointsMode: _timePointsMode,
        timerUi: _unit == CountUnit.seconds && _timerUi,
        supportsWeight: _supportsWeight,
        weightThreshold: wTh,
        weightMultiplier: _supportsWeight ? wMul : null,
      );
      ref.invalidate(roomExercisesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create exercise: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final maxScrollH = MediaQuery.of(context).size.height * 0.62;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JarsColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Custom exercise',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: JarsColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose how logging and points work for this move.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: JarsColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxScrollH),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(_name, 'Name'),
                    const SizedBox(height: 16),
                    Text(
                      'Count as',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: JarsColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<CountUnit>(
                      segments: const [
                        ButtonSegment(
                          value: CountUnit.reps,
                          label: Text('Reps'),
                          tooltip: 'Count each repetition',
                        ),
                        ButtonSegment(
                          value: CountUnit.seconds,
                          label: Text('Seconds'),
                          tooltip: 'Time in seconds',
                        ),
                        ButtonSegment(
                          value: CountUnit.minutes,
                          label: Text('Minutes'),
                          tooltip: 'Whole minutes',
                        ),
                      ],
                      selected: {_unit},
                      onSelectionChanged: (s) {
                        setState(() {
                          _unit = s.first;
                          if (_unit != CountUnit.seconds) _timerUi = false;
                        });
                      },
                    ),
                    if (_unit == CountUnit.seconds) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Time scoring',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<TimePointsMode>(
                        segments: const [
                          ButtonSegment(
                            value: TimePointsMode.perSecond,
                            label: Text('Per second'),
                          ),
                          ButtonSegment(
                            value: TimePointsMode.perMinute,
                            label: Text('Per minute of time'),
                          ),
                        ],
                        selected: {_timePointsMode},
                        onSelectionChanged: (s) {
                          setState(() => _timePointsMode = s.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Stopwatch UI',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          'Tap start/stop instead of entering seconds manually.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: JarsColors.textSecondary,
                          ),
                        ),
                        value: _timerUi,
                        onChanged: (v) => setState(() => _timerUi = v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _field(
                      _points,
                      _pointsLabel,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      helperText: _pointsHelper,
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Extra points for weight',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: JarsColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Add bonus points per threshold of weight (e.g. per 45 lb).',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: JarsColors.textSecondary,
                        ),
                      ),
                      value: _supportsWeight,
                      onChanged: (v) => setState(() => _supportsWeight = v),
                    ),
                    if (_supportsWeight) ...[
                      const SizedBox(height: 8),
                      _field(
                        _weightThreshold,
                        'Weight threshold',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        helperText:
                            'Bonus applies each time weight reaches another full threshold (e.g. 45).',
                      ),
                      const SizedBox(height: 12),
                      _field(
                        _weightMultiplier,
                        'Bonus per threshold',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        helperText:
                            'Points added per threshold step (default 1).',
                      ),
                    ],
                    const SizedBox(height: 16),
                    _field(_icon, 'Icon (emoji)'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    TextInputType? keyboardType,
    String? helperText,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboardType ?? TextInputType.text,
      style: GoogleFonts.inter(
        fontSize: 16,
        color: JarsColors.textPrimary,
      ),
      cursorColor: JarsColors.primary,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: JarsColors.textSecondary,
        ),
        helperStyle: GoogleFonts.inter(
          fontSize: 12,
          color: JarsColors.textSecondary,
        ),
        filled: true,
        fillColor: JarsColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JarsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JarsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JarsColors.primary),
        ),
      ),
    );
  }
}
