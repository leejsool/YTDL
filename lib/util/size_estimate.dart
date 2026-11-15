/// 다운로드 전에 보여 줄 "예상 용량" 계산.
///
/// yt-dlp 가 화질 제한(-S res:H,vcodec:h264,acodec:m4a)에서 실제로 고르는 포맷과
/// 같은 규칙으로 스트림을 골라 용량을 더한다.
///   영상: 해상도 <= H 중 가장 큰 것 -> H.264 우선 -> 용량(정보가 있는 쪽) 큰 것
///   소리: AAC(m4a) 우선 -> 채널 수 많은 것 -> 용량 큰 것
/// 용량 정보가 없는 스트림은 비트레이트 x 길이로 어림한다. 그마저 없으면 null(표시 안 함).
library;

import '../models.dart';

/// MP3 는 VBR(V0) 로 만들어 평균 비트레이트가 내용에 따라 다르다. 대략값(kbps).
const int mp3ApproxKbps = 230;

/// H.264 만 우선하고(-S vcodec:h264), 그 밖의 코덱끼리는 순서를 두지 않는다.
/// (같은 해상도에 H.264 가 없으면 yt-dlp 는 코덱이 아니라 용량이 큰 쪽을 고른다.)
int _rank(String vcodec) => vcodec.startsWith('avc1') ? 0 : 1;

int? _bytes(FormatInfo f, int durationSeconds) {
  if (f.filesize != null && f.filesize! > 0) return f.filesize;
  if (f.tbr != null && f.tbr! > 0 && durationSeconds > 0) {
    return (f.tbr! * 1000 / 8 * durationSeconds).round();
  }
  return null;
}

FormatInfo? _pickVideo(List<FormatInfo> formats, int? maxHeight, int duration) {
  final cands = formats.where((f) => f.hasVideo && f.height != null).toList();
  if (cands.isEmpty) return null;
  // 제한 높이 이하가 하나도 없으면(예: 144p 영상에 360p 제한 X) 가장 낮은 것으로.
  var pool = maxHeight == null ? cands : cands.where((f) => f.height! <= maxHeight).toList();
  if (pool.isEmpty) {
    final minH = cands.map((f) => f.height!).reduce((a, b) => a < b ? a : b);
    pool = cands.where((f) => f.height == minH).toList();
  }
  pool.sort((a, b) {
    var c = b.height!.compareTo(a.height!);
    if (c != 0) return c;
    c = _rank(a.vcodec).compareTo(_rank(b.vcodec));
    if (c != 0) return c;
    c = (b.filesize ?? 0).compareTo(a.filesize ?? 0);
    if (c != 0) return c;
    return (b.tbr ?? 0).compareTo(a.tbr ?? 0);
  });
  return pool.first;
}

FormatInfo? _pickAudio(List<FormatInfo> formats, {String? codecPrefix}) {
  var cands = formats.where((f) => f.hasAudio && !f.hasVideo).toList();
  if (codecPrefix != null) {
    final only = cands.where((f) => f.acodec.startsWith(codecPrefix)).toList();
    if (only.isNotEmpty) cands = only;
  }
  if (cands.isEmpty) return null;
  cands.sort((a, b) {
    final aa = a.acodec.startsWith('mp4a') ? 0 : 1;
    final bb = b.acodec.startsWith('mp4a') ? 0 : 1;
    var c = aa.compareTo(bb);
    if (c != 0) return c;
    c = (b.audioChannels ?? 0).compareTo(a.audioChannels ?? 0);
    if (c != 0) return c;
    c = (b.filesize ?? 0).compareTo(a.filesize ?? 0);
    if (c != 0) return c;
    return (b.tbr ?? 0).compareTo(a.tbr ?? 0);
  });
  return cands.first;
}

/// 영상(mp4) 예상 바이트. [fraction] 은 구간 자르기 시 전체 대비 비율(0~1).
int? estimateVideoBytes(MediaInfo info, int? maxHeight, {double fraction = 1}) {
  final d = info.durationSeconds;
  final v = _pickVideo(info.formats, maxHeight, d);
  if (v == null) return null;
  var total = _bytes(v, d);
  if (total == null) return null;
  if (!v.hasAudio) {
    final a = _pickAudio(info.formats);
    final ab = a == null ? null : _bytes(a, d);
    if (ab != null) total += ab;
  }
  return (total * fraction.clamp(0.0, 1.0)).round();
}

/// 음원 예상 바이트. format: mp3 | m4a | opus
int? estimateAudioBytes(MediaInfo info, String format, {double fraction = 1}) {
  final d = info.durationSeconds;
  int? total;
  switch (format) {
    case 'mp3':
      if (d > 0) total = (mp3ApproxKbps * 1000 / 8 * d).round();
    case 'm4a':
      final a = _pickAudio(info.formats, codecPrefix: 'mp4a');
      total = a == null ? null : _bytes(a, d);
    case 'opus':
      final a = _pickAudio(info.formats, codecPrefix: 'opus');
      total = a == null ? null : _bytes(a, d);
  }
  if (total == null) return null;
  return (total * fraction.clamp(0.0, 1.0)).round();
}

/// 바이트 -> "28.5MB" / "1.3GB" (탐색기와 같은 1024 단위).
String formatBytes(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${(bytes / (1024 * mb)).toStringAsFixed(1)}GB';
  final m = bytes / mb;
  if (m >= 100) return '${m.round()}MB';
  if (m >= 1) return '${m.toStringAsFixed(1)}MB';
  return '${(bytes / 1024).round()}KB';
}
