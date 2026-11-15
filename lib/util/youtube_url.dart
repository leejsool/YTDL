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
