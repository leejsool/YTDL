import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// 유튜브가 공개하는 간단 정보(oEmbed)로 제목·채널·썸네일만 아주 빨리(0.3초 안팎) 가져온다.
/// yt-dlp 의 전체 조회(3~5초)가 끝나기 전에 화면에 먼저 보여 주는 용도이며, 길이·화질 정보는 없다.
/// 실패하거나 느리면 null (그때는 기다리면 된다).
Future<MediaInfo?> fetchQuickInfo(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final uri = Uri.https('www.youtube.com', '/oembed', {'url': url, 'format': 'json'});
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 3));
    final res = await req.close().timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) return null;
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 3));
    final j = jsonDecode(body) as Map<String, dynamic>;
    final title = (j['title'] ?? '').toString();
    if (title.isEmpty) return null;
    return MediaInfo(
      id: '',
      title: title,
      uploader: (j['author_name'] ?? '').toString(),
      url: url,
      durationSeconds: 0,
      thumbnail: j['thumbnail_url'] as String?,
    );
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

final _idRes = [
  RegExp(r'[?&]v=([\w-]{11})'),
  RegExp(r'youtu\.be/([\w-]{11})'),
  RegExp(r'youtube(?:-nocookie)?\.com/(?:shorts|embed|live|v)/([\w-]{11})'),
];

/// 주소에서 영상 ID(11자)를 뽑는다. 못 찾으면 null.
String? youtubeVideoId(String url) {
  for (final re in _idRes) {
    final m = re.firstMatch(url);
    if (m != null) return m.group(1);
  }
  return null;
}

/// 네트워크 없이 영상 ID 만으로 만드는 임시 정보. 썸네일 주소는 ID 로 정해져 있어서
/// 조회 버튼을 누르는 즉시 썸네일을 띄울 수 있다. 제목은 나중에 채워진다.
MediaInfo? quickInfoFromId(String url) {
  final id = youtubeVideoId(url);
  if (id == null) return null;
  return MediaInfo(
    id: id,
    title: '정보를 불러오는 중…',
    uploader: '',
    url: url,
    durationSeconds: 0,
    thumbnail: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
  );
}
