import 'package:flutter/material.dart';

class Level {
  final int level;
  final double threshold;
  final String title;
  final Color color;
  final String icon;
  final String description;

  const Level({
    required this.level,
    required this.threshold,
    required this.title,
    required this.color,
    required this.icon,
    required this.description,
  });
}
