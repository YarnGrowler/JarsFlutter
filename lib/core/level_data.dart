import 'package:flutter/material.dart';
import '../models/level.dart';

const kLevelThresholds = <Level>[
  Level(level: 1, threshold: 0, title: 'Iron I', color: Color(0xFF434343), icon: '\u{1FAA8}', description: 'Just getting started'),
  Level(level: 2, threshold: 100, title: 'Iron II', color: Color(0xFF555555), icon: '\u{1FAA8}', description: 'Building a foundation'),
  Level(level: 3, threshold: 250, title: 'Iron III', color: Color(0xFF666666), icon: '\u{1FAA8}', description: 'Finding the rhythm'),
  Level(level: 4, threshold: 400, title: 'Bronze I', color: Color(0xFFCD7F32), icon: '\u{1F949}', description: 'Warming up'),
  Level(level: 5, threshold: 750, title: 'Bronze II', color: Color(0xFFDAA520), icon: '\u{1F949}', description: 'Steady improvement'),
  Level(level: 6, threshold: 1100, title: 'Bronze III', color: Color(0xFFFFB347), icon: '\u{1F949}', description: 'Shining brighter'),
  Level(level: 7, threshold: 1500, title: 'Silver I', color: Color(0xFFC0C0C0), icon: '\u{1F948}', description: 'Getting serious'),
  Level(level: 8, threshold: 2000, title: 'Silver II', color: Color(0xFFD3D3D3), icon: '\u{1F948}', description: 'Polishing technique'),
  Level(level: 9, threshold: 2650, title: 'Silver III', color: Color(0xFFE6E6E6), icon: '\u{1F948}', description: 'Consistency pays off'),
  Level(level: 10, threshold: 3500, title: 'Gold I', color: Color(0xFFFFD700), icon: '\u{1F947}', description: 'Aiming for greatness'),
  Level(level: 11, threshold: 4300, title: 'Gold II', color: Color(0xFFFFC107), icon: '\u{1F947}', description: 'Turning sweat into gold'),
  Level(level: 12, threshold: 5000, title: 'Gold III', color: Color(0xFFFFB300), icon: '\u{1F947}', description: 'Striving for excellence'),
  Level(level: 13, threshold: 6000, title: 'Gold IV', color: Color(0xFFFFB300), icon: '\u{1F947}', description: 'Gold is a currency'),
  Level(level: 14, threshold: 7000, title: 'Platinum I', color: Color(0xFFE5E4E2), icon: '\u{2712}\u{FE0F}', description: 'Beginning of the end'),
  Level(level: 15, threshold: 8200, title: 'Platinum II', color: Color(0xFFD9D9D9), icon: '\u{2712}\u{FE0F}', description: 'Absolutely locked in'),
  Level(level: 16, threshold: 9000, title: 'Platinum III', color: Color(0xFFC0C0C0), icon: '\u{2712}\u{FE0F}', description: 'No turning back'),
  Level(level: 17, threshold: 10000, title: 'MiniDiamond I', color: Color(0xFFB9F2FF), icon: '\u{1F48E}', description: 'MiniDiamonds are the best diamonds'),
  Level(level: 18, threshold: 12000, title: 'Diamond I', color: Color(0xFFB9F2FF), icon: '\u{1F48E}', description: 'Carrying the team'),
  Level(level: 19, threshold: 13500, title: 'Diamond II', color: Color(0xFFAFEEEE), icon: '\u{1F48E}', description: 'Edging the summit'),
  Level(level: 20, threshold: 15250, title: 'Diamond III', color: Color(0xFFADD8E6), icon: '\u{1F48E}', description: 'Unstoppable'),
  Level(level: 21, threshold: 19500, title: 'Legend I', color: Color(0xFF8A2BE2), icon: '\u{1F6E1}\u{FE0F}', description: 'Beyond the ordinary'),
  Level(level: 22, threshold: 23000, title: 'Legend II', color: Color(0xFF9370DB), icon: '\u{1F6E1}\u{FE0F}', description: 'A tale of legends'),
  Level(level: 23, threshold: 27000, title: 'Legend III', color: Color(0xFFBA55D3), icon: '\u{1F6E1}\u{FE0F}', description: 'The ultimate achievement'),
  Level(level: 24, threshold: 33000, title: 'Champion', color: Color(0xFF8B0000), icon: '\u{1F3C6}', description: 'Certified beast'),
  Level(level: 25, threshold: 38000, title: 'Champion II', color: Color(0xFFAF4500), icon: '\u{1F3C6}', description: 'Wild animal'),
  Level(level: 26, threshold: 44000, title: 'Champion III', color: Color(0xFFFF4500), icon: '\u{1F3C6}', description: 'This is not a joke'),
  Level(level: 27, threshold: 50000, title: 'Radiant', color: Color(0xFFFFCC55), icon: '\u{2728}', description: 'Are we there yet?'),
  Level(level: 28, threshold: 54000, title: 'Radiant II', color: Color(0xFFFFAE00), icon: '\u{1F4AB}', description: 'Straight out of jail'),
  Level(level: 29, threshold: 58000, title: 'Radiant III', color: Color(0xFFFF9944), icon: '\u{2728}', description: 'You thought you could catch up'),
  Level(level: 30, threshold: 62000, title: 'Ascendant I', color: Color(0xFF50C878), icon: '\u{1F30C}', description: 'Beyond the ordinary'),
  Level(level: 31, threshold: 72000, title: 'Ascendant II', color: Color(0xFF4EAA6E), icon: '\u{1F30C}', description: 'Relentless pursuit'),
  Level(level: 32, threshold: 83000, title: 'Ascendant III', color: Color(0xFF4B7764), icon: '\u{1F30C}', description: 'The voices told me'),
  Level(level: 33, threshold: 93000, title: 'Ascendant IV', color: Color(0xFF4B7764), icon: '\u{2728}', description: 'You are alone'),
  Level(level: 34, threshold: 105000, title: 'Skibidi I', color: Color(0xFFB5988D), icon: '\u{1F6BD}', description: 'Breaking records'),
  Level(level: 35, threshold: 120000, title: 'Skibidi II', color: Color(0xFFC6A09A), icon: '\u{1F6BD}', description: 'Limited edition'),
  Level(level: 36, threshold: 135000, title: 'Skibidi III', color: Color(0xFFD4B6A5), icon: '\u{1F6BD}', description: "Don't try this at home"),
];

Level getLevelForScore(double totalScore) {
  Level current = kLevelThresholds.first;
  for (final level in kLevelThresholds) {
    if (totalScore >= level.threshold) {
      current = level;
    } else {
      break;
    }
  }
  return current;
}

double getProgressToNextLevel(double totalScore) {
  final currentLevel = getLevelForScore(totalScore);
  final currentIndex = kLevelThresholds.indexOf(currentLevel);

  if (currentIndex >= kLevelThresholds.length - 1) return 1.0;

  final nextLevel = kLevelThresholds[currentIndex + 1];
  final pointsInLevel = totalScore - currentLevel.threshold;
  final levelRange = nextLevel.threshold - currentLevel.threshold;

  return (pointsInLevel / levelRange).clamp(0.0, 1.0);
}

double getPointsToNextLevel(double totalScore) {
  final currentLevel = getLevelForScore(totalScore);
  final currentIndex = kLevelThresholds.indexOf(currentLevel);

  if (currentIndex >= kLevelThresholds.length - 1) return 0;

  final nextLevel = kLevelThresholds[currentIndex + 1];
  return nextLevel.threshold - totalScore;
}
