/// 글 안에서 유튜브 주소(youtube.com / youtu.be / music.youtube.com 등)를 찾는다.
/// 클립보드를 자동으로 읽을 때, 유튜브가 아닌 주소나 일반 글은 건드리지 않으려고 쓴다.
final _youtubeRe = RegExp(
  r'https?://(?:[a-z0-9-]+\.)*(?:youtube\.com|youtu\.be|youtube-nocookie\.com)(?![\w.-])(?:[/?#][^\s]*)?',
  caseSensitive: false,
);

/// [text] 안의 첫 유튜브 주소. 없으면 null.
String? findYoutubeUrl(String? text) {
  if (text == null) return null;
  return _youtubeRe.firstMatch(text)?.group(0);
}

/// 주소의 `list=` 재생목록 ID. 없거나, 받을 수 없는 종류면 null.
/// (RD… 는 유튜브가 즉석에서 만드는 "믹스"라 끝이 없고, WL·LL 은 로그인이 필요한 개인 목록이다.)
String? playlistIdOf(String url) {
  final id = Uri.tryParse(url)?.queryParameters['list'];
  if (id == null || id.isEmpty) return null;
  if (id.startsWith('RD') || id == 'WL' || id == 'LL') return null;
  return id;
}

/// 영상 하나가 아니라 재생목록 자체를 가리키는 주소인가(`/playlist?list=…`).
/// `watch?v=…&list=…` 처럼 영상이 지정돼 있으면 그 영상 하나로 본다.
bool isPlaylistOnlyUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || playlistIdOf(url) == null) return false;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be') return false;
  return !uri.queryParameters.containsKey('v') &&
      (uri.path == '/playlist' || uri.path.startsWith('/playlist'));
}

/// 재생목록 ID 로 만든 표준 주소.
String playlistUrlFor(String listId) =>
    'https://www.youtube.com/playlist?list=$listId';
