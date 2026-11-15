/// 초 -> "m:ss" 또는 "h:mm:ss".
String formatSeconds(int total) {
  if (total < 0) total = 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// 밀리초 -> "m:ss.t" / "h:mm:ss.t" (0.1초 단위. 미리듣기에서 쓴다).
String formatMs(int ms) {
  if (ms < 0) ms = 0;
  final tenths = (ms / 100).round();
  final t = tenths % 10;
  return '${formatSeconds(tenths ~/ 10)}.$t';
}

/// "83.5", "1:23.4", "1:02:03.4" -> 밀리초. 형식이 틀리면 null.
int? parseMs(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length > 3) return null;
  var seconds = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final isLast = i == parts.length - 1;
    final v = isLast ? double.tryParse(parts[i].trim()) : int.tryParse(parts[i].trim())?.toDouble();
    if (v == null || v < 0) return null;
    seconds = seconds * 60 + v;
  }
  return (seconds * 1000).round();
}

/// "83", "1:23", "1:02:03" -> 초. 형식이 틀리면 null.
int? parseSeconds(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length > 3) return null;
  var total = 0;
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null || n < 0) return null;
    total = total * 60 + n;
  }
  return total;
}
