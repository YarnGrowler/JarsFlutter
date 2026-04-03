import 'dart:io';

/// Reads the first `.env` found walking up from [Directory.current].
Future<Map<String, String>> readLocalEnvPairs() async {
  final file = await _findEnvFile();
  if (file == null) return {};

  final merged = <String, String>{};
  final content = await file.readAsString();
  for (final rawLine in content.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trim();
    final idx = line.indexOf('=');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    var value = line.substring(idx + 1).trim();
    if (value.length >= 2) {
      final q = value[0];
      if ((q == '"' || q == "'") && value.endsWith(q)) {
        value = value.substring(1, value.length - 1);
      }
    }
    merged[key] = value;
  }
  return merged;
}

Future<File?> _findEnvFile() async {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final f = File('${dir.path}${Platform.pathSeparator}.env');
    if (await f.exists()) return f;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
