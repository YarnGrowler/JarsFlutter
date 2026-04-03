import 'package:flutter/material.dart';

/// Design tokens for the Log screen (JARS spec).
const Color kLogPurple = Color(0xFF7C6FFF);
const Color kLogSurface = Color(0xFF1A1A26);
const Color kLogGold = Color(0xFFFFB800);
const Color kLogGoldMuted = Color(0x99FFB800);
const Color kLogText = Color(0xFFEEEEFF);
const Color kLogPurpleGlow = Color(0x607C6FFF);
const Color kLogPurplePulse = Color(0x307C6FFF);
const Color kLogPurpleTint = Color(0x157C6FFF);
const Color kLogNearBlack = Color(0xFF08080E);

const Duration kLogCrossfade = Duration(milliseconds: 150);
const Duration kRepBumpTotal = Duration(milliseconds: 180);
const Duration kPointsAnimUp = Duration(milliseconds: 300);
const Duration kPointsAnimDown = Duration(milliseconds: 150);

Color categoryLetterColor(String category) {
  switch (category) {
    case 'Upper Body':
      return kLogPurple;
    case 'Core':
      return const Color(0xFF1ED97A);
    case 'Lower Body':
      return kLogGold;
    case 'Cardio':
      return const Color(0xFF38BDF8);
    case 'Full Body':
    case 'Strength':
      return const Color(0xFFFF3D55);
    default:
      return kLogPurple;
  }
}

bool exerciseIconShowsEmoji(String icon) {
  final t = icon.trim();
  if (t.isEmpty) return false;
  if (t.length == 1 && RegExp(r'[A-Za-z]').hasMatch(t)) return false;
  if (RegExp(r'^[A-Za-z0-9]+$').hasMatch(t)) return false;
  return true;
}
