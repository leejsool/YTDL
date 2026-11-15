/// 파일 이름 만들기/해석. 잘린 구간은 항상 "원본 영상 기준" 시각으로 이름에 적는다.
library;

/// 5 -> "0m05s", 6.3 -> "0m06.3s", 3723 -> "1h02m03s".  ':' 는 파일명에 못 쓴다.
String clockTag(num seconds) {
  final tenths = (seconds * 10).round();
  final whole = tenths ~/ 10;
  final frac = tenths % 10;
  final h = whole ~/ 3600;
  final m = (whole % 3600) ~/ 60;
  final s = (whole % 60).toString().padLeft(2, '0');
  final fracStr = frac == 0 ? '' : '.$frac';
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}m$s${fracStr}s';
  return '${m}m$s${fracStr}s';
}

String cutSuffix(num startSec, num endSec) => ' (cut ${clockTag(startSec)}-${clockTag(endSec)})';

final RegExp _cutTail = RegExp(r' \(cut [^)]*\)$');

/// "Title (cut 0m05s-0m12s)" -> "Title"
String stripCut(String name) => name.replaceFirst(_cutTail, '');

final RegExp _clockRe = RegExp(r'^(?:(\d+)h)?(\d+)m(\d+(?:\.\d+)?)s$');

/// clockTag 의 반대: "1h02m03.5s" -> 3723.5.  형식이 아니면 null.
double? parseClockTag(String tag) {
  final m = _clockRe.firstMatch(tag);
  if (m == null) return null;
  final h = int.tryParse(m.group(1) ?? '0') ?? 0;
  final min = int.parse(m.group(2)!);
  final s = double.parse(m.group(3)!);
  return h * 3600 + min * 60 + s;
}

final RegExp _cutParse = RegExp(r' \(cut ([^)]+)-([^)]+)\)$');

/// "Title (cut 0m05s-0m12s)" -> (5.0, 12.0).  이 앱이 만든 이름이 아니면 null.
({double start, double end})? parseCutTag(String name) {
  final m = _cutParse.firstMatch(name);
  if (m == null) return null;
  final a = parseClockTag(m.group(1)!);
  final b = parseClockTag(m.group(2)!);
  if (a == null || b == null || b <= a) return null;
  return (start: a, end: b);
}

/// 경로에서 확장자를 뺀 파일 이름 (Windows '\' 와 Android '/' 모두).
String baseNameOf(String path) {
  final file = path.split(RegExp(r'[\\/]')).last;
  final dot = file.lastIndexOf('.');
  return dot > 0 ? file.substring(0, dot) : file;
}

String extensionOf(String path) {
  final file = path.split(RegExp(r'[\\/]')).last;
  final dot = file.lastIndexOf('.');
  return dot > 0 ? file.substring(dot + 1) : '';
}
