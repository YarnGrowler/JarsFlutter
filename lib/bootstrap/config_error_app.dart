import 'package:flutter/material.dart';

/// Shown when Supabase URL/anon key are missing so [main] never throws before [runApp].
class ConfigErrorApp extends StatelessWidget {
  final String details;

  const ConfigErrorApp({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF08080E),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'JARS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: Color(0xFF7C6FFF),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Supabase is not configured',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFEEEEFF),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  details,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFFB0B0C0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
