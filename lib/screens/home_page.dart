import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../util/names.dart';
import '../util/oembed.dart';
import '../util/preview_renderer.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../util/size_estimate.dart';
import '../util/time_format.dart';
import '../util/youtube_url.dart';
import '../widgets/gain_selector.dart';
import '../widgets/loading_stripes.dart';
import '../widgets/range_preview.dart';
import '../widgets/trim_selector.dart';
import '../widgets/pill_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.backend,
    required this.recent,
    required this.editController,
    required this.videoController,
    required this.videoRecent,
    required this.settings,
  });

  final Backend backend;

  /// 받은 음원을 최근 목록에 올리고, "편집하기"로 편집 탭에 넘기는 데 쓴다.
  final RecentStore recent;
  final EditController editController;

  /// 받은 영상을 영상 편집 탭에 넘기는 데 쓴다.
  final EditController videoController;
  final RecentStore videoRecent;

  /// 옵션 탭의 기본값(음원 형식, 영상 화질).
  final AppSettings settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Backend get _b => widget.backend;
  late final PreviewRenderer _preview = PreviewRenderer(_b);
  final _urlCtl = TextEditingController();

  // 엔진 준비
  bool _ready = false;
  String _setupMsg = '준비 중…';
  double? _setupProgress;
  String? _setupError;

  // 영상 정보
  MediaInfo? _info;
  bool _fetching = false;
  String _fetchUrl = '';
  int _fetchGen = 0; // 조회 중에 새 주소를 넣으면 이전 조회 결과는 버리기 위한 번호
  // 조회가 끝나기 전에 먼저 보여 주는 간단 정보(제목·채널·썸네일), 그리고 최근 조회 결과 캐시.
  MediaInfo? _quick;
  final Map<String, (MediaInfo, DateTime)> _infoCache = {};
  String? _fetchError;

  // 옵션
  MediaKind _kind = MediaKind.audio;
  late String _audioFormat = widget.settings.audioFormat;
  AudioGain _gain = const AudioGain.none();
  late int? _maxHeight = widget.settings.maxHeight;
  bool _trimOn = false;
  int _trimStart = 0;
  int _trimEnd = 0;

  // 다운로드
  bool _downloading = false;
  DownloadProgress? _progress;
  CancelToken? _token;
  DownloadResult? _result;
  String? _dlError;

  // 방금 받은 음원(편집 탭으로 넘길 수 있다)
  SavedAudio? _saved;
  SavedAudio? _savedVideo;

  static final _urlRe = RegExp(r'https?://[^\s]+');

  @override
  void initState() {
    super.initState();
    _b.onSharedText = _acceptUrl;
    widget.settings.addListener(_onSettings);
    _setup();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettings);
    _urlCtl.dispose();
    super.dispose();
  }

  /// 옵션 탭에서 기본값을 바꾸면 지금 선택에도 바로 반영한다.
  void _onSettings() {
    if (!mounted || _downloading) return;
    setState(() {
      _audioFormat = widget.settings.audioFormat;
      _maxHeight = widget.settings.maxHeight;
    });
  }

  Future<void> _setup() async {
    setState(() {
      _ready = false;
      _setupError = null;
      _setupMsg = '준비 중…';
      _setupProgress = null;
    });
    try {
      await _b.prepare((msg, p) {
        if (mounted) {
          setState(() {
            _setupMsg = msg;
            _setupProgress = p;
          });
        }
      });
      final shared = await _b.takeInitialSharedText();
      if (!mounted) return;
      setState(() => _ready = true);
      if (shared != null) {
        _acceptUrl(shared);
      } else {
        await _acceptClipboardOnStart();
      }
    } catch (e) {
      if (mounted) setState(() => _setupError = _msg(e));
    }
  }

  /// 앱을 시작할 때 클립보드에 유튜브 주소가 있으면 입력칸에 넣고 바로 조회한다.
  /// (유튜브 주소가 아니거나 클립보드를 못 읽으면 아무 일도 하지 않는다.)
  Future<void> _acceptClipboardOnStart() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final url = findYoutubeUrl(data?.text);
      if (!mounted || url == null || _urlCtl.text.trim().isNotEmpty) return;
      _acceptUrl(url);
    } catch (_) {
      // 클립보드 접근이 막혀 있어도 앱은 그대로 쓸 수 있다.
    }
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// 공유로 받은 텍스트나 붙여넣은 글에서 URL만 뽑아 바로 조회한다.
  void _acceptUrl(String text) {
    final m = _urlRe.firstMatch(text);
    _urlCtl.text = m?.group(0) ?? text.trim();
    _fetch();
  }

  /// 주소칸을 비운다. 조회 중이었다면 그 조회도 멈추고 임시로 보이던 카드를 치운다.
  void _clearUrl() {
    _urlCtl.clear();
    if (_fetching) {
      _fetchGen++;
      setState(() {
        _fetching = false;
        _quick = null;
        _fetchError = null;
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _acceptUrl(data!.text!);
  }

  Future<void> _fetch() async {
    if (!_ready || _downloading) return;
    final raw = _urlCtl.text.trim();
    final url = _urlRe.firstMatch(raw)?.group(0);
    final gen = ++_fetchGen;
    if (url == null) {
      setState(() {
        _fetching = false;
        _quick = null;
        _fetchError = '올바른 링크(https://…)를 입력해 주세요.';
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    // 최근 30분 안에 조회한 영상이면 바로 보여 준다(소리 주소는 몇 시간 동안 유효).
    final cached = _infoCache[url];
    if (cached != null && DateTime.now().difference(cached.$2).inMinutes < 30) {
      setState(() {
        _fetchError = null;
        _result = null;
        _dlError = null;
        _saved = null;
        _savedVideo = null;
        _fetching = false;
        _quick = null;
        _info = cached.$1;
        _trimStart = 0;
        _trimEnd = cached.$1.durationSeconds;
        _trimOn = false;
        _gain = const AudioGain.none();
      });
      return;
    }
    setState(() {
      _fetching = true;
      _fetchUrl = url;
      _trimOn = false;
      _fetchError = null;
      _quick = quickInfoFromId(url); // 썸네일은 영상 ID 만으로 바로 띄운다
      _info = null;
      _result = null;
      _dlError = null;
      _saved = null;
      _savedVideo = null;
    });
    // 전체 조회(수 초)와 동시에 제목·썸네일만 먼저 가져와 보여 준다.
    unawaited(
      fetchQuickInfo(url).then((q) {
        if (q != null && mounted && gen == _fetchGen && _info == null) {
          setState(() => _quick = q);
        }
      }),
    );
    try {
      final info = await _b.fetchInfo(url);
      if (!mounted) return;
      _infoCache[url] = (info, DateTime.now());
      if (gen != _fetchGen) return; // 그 사이 다른 주소를 넣었다
      _infoCache[url] = (info, DateTime.now());
      setState(() {
        _quick = null;
        _info = info;
        _trimStart = 0;
        _trimEnd = info.durationSeconds;
        _gain = const AudioGain.none();
      });
      // 조회 중에 미리 펼쳐 둔 구간 자르기가 있으면 이제 소리를 미리 받아 둔다.
      if (_trimOn && info.durationSeconds <= 1800) {
        unawaited(_preview.prefetch(info.url, audioUrl: info.previewAudioUrl));
      }
    } catch (e) {
      if (mounted && gen == _fetchGen) setState(() => _fetchError = _msg(e));
    } finally {
      if (mounted && gen == _fetchGen) {
        setState(() {
          _fetching = false;
          _quick = null;
        });
      }
    }
  }

  Future<void> _download() async {
    final info = _info;
    if (info == null) return;
    final trim = _trimOn && info.durationSeconds > 0;
    final token = CancelToken();
    setState(() {
      _downloading = true;
      _token = token;
      _progress = const DownloadProgress(stage: '시작하는 중…');
      _result = null;
      _dlError = null;
      _saved = null;
      _savedVideo = null;
    });
    try {
      final options = DownloadOptions(
        kind: _kind,
        audioFormat: _audioFormat,
        maxHeight: _maxHeight,
        trimStart: trim ? _trimStart : null,
        trimEnd: trim ? _trimEnd : null,
        gain: _kind == MediaKind.audio ? _gain : const AudioGain.none(),
        infoJson: info.reusableJson,
      );
      final r = await _b.download(info.url, options, (p) {
        if (mounted) setState(() => _progress = p);
      }, token);
      if (!mounted) return;
      setState(() {
        _result = r;
        // 음원이면 편집 탭에서 열 수 있게 준비하고, 최근 파일 목록에도 올린다.
        final path = r.filePath;
        if (_kind == MediaKind.audio && path != null) {
          _saved = SavedAudio(
            title: stripCut(baseNameOf(path)),
            path: path,
            location: r.location,
            srcStart: (options.trimStart ?? 0).toDouble(),
            srcEnd: (options.trimEnd ?? info.durationSeconds).toDouble(),
            sourceLabel: '원본 영상',
          );
        }
        // 영상이면 영상 편집 탭에서 열 수 있게 준비한다.
        if (_kind == MediaKind.video && path != null) {
          _savedVideo = SavedAudio(
            title: stripCut(baseNameOf(path)),
            path: path,
            location: r.location,
            srcStart: (options.trimStart ?? 0).toDouble(),
            srcEnd: (options.trimEnd ?? info.durationSeconds).toDouble(),
            sourceLabel: '원본 영상',
          );
        }
      });
      if (_saved != null) widget.recent.add(_saved!);
      if (_savedVideo != null) widget.videoRecent.add(_savedVideo!);
    } on CancelledException {
      if (mounted) setState(() => _dlError = '취소했습니다.');
    } catch (e) {
      if (mounted) setState(() => _dlError = _msg(e));
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _token = null;
        });
      }
    }
  }

  Future<void> _updateEngine() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('엔진 업데이트 확인 중…')));
    try {
      final r = await _b.updateEngine();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('엔진 업데이트: $r')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('업데이트 실패: ${_msg(e)}')));
    }
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 590;
        final gutter = wide ? 30.0 : 16.0;
        final pinFooter = box.maxHeight >= 420;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        wide ? 26 : 16,
                        gutter,
                        20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(wide),
                          const SizedBox(height: 20),
                          if (!_ready)
                            _buildSetup()
                          else ...[
                            _buildMain(wide),
                            if (!pinFooter) ...[
                              const SizedBox(height: 18),
                              _buildFooter(wide, gutter),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_ready && pinFooter) _buildFooter(wide, gutter),
          ],
        );
      },
    );
  }

  Widget _buildHeader(bool wide) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '다운로드',
                style:
                    (wide
                            ? theme.textTheme.headlineLarge
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
              ),
              const SizedBox(height: 4),
              Text(
                '유튜브 링크를 음원이나 영상으로 저장하세요.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_ready) ...[
          const SizedBox(width: 8),
          if (wide)
            PillButton(
              onPressed: _downloading ? null : _updateEngine,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('엔진 업데이트 확인'),
            )
          else
            IconButton(
              tooltip: '엔진 업데이트 확인',
              onPressed: _downloading ? null : _updateEngine,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ],
    );
  }

  Widget _buildSetup() {
    if (_setupError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('준비에 실패했습니다', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_setupError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _setup, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_setupMsg),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _setupProgress),
        ],
      ),
    );
  }

  Widget _buildMain(bool wide) {
    final info = _info;
    // 조회 중에도 화면 구성을 미리 보여 준다(흐리게, 누를 수 없게). 아직 모르는 값은 ?? 로 표시한다.
    final loading = info == null && _fetching;
    final shown =
        info ??
        (loading
            ? (_quick ??
                  MediaInfo(
                    id: '',
                    title: '정보를 불러오는 중…',
                    uploader: '',
                    url: _fetchUrl,
                    durationSeconds: 0,
                  ))
            : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildUrlRow(),
        if (_fetchError != null) _errorText(_fetchError!),
        if (_fetching)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
        if (shown != null) ...[
          const SizedBox(height: 16),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 9, child: _buildInfoCard(shown, wide, loading: loading)),
                const SizedBox(width: 16),
                Expanded(
                  flex: 11,
                  child: _buildOptions(shown, loading: loading),
                ),
              ],
            )
          else ...[
            _buildInfoCard(shown, wide, loading: loading),
            const SizedBox(height: 12),
            _buildOptions(shown, loading: loading),
          ],
        ],
        if (info == null && !_fetching)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: _buildEmpty(),
          ),
      ],
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.video_library_outlined, color: colors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              '저장할 영상 링크를 입력하세요',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 주소칸 안에 나란히 붙일 작은 아이콘 버튼(기본 아이콘 버튼은 최소 48 크기라 서로 멀어 보인다).
  Widget _smallIconButton(IconData icon, String tooltip, VoidCallback? onTap) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 18,
        child: SizedBox(
          width: 30,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? colors.outline : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildUrlRow() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('유튜브 링크', style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlCtl,
                enabled: !_downloading,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                decoration: InputDecoration(
                  // 안내 문구는 글자를 한 자라도 치면 사라진다. 링크 아이콘도 안내 문구의 일부로 같이 사라진다.
                  hint: Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '여기에 유튜브 주소를 입력하세요',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: .7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 0,
                    minHeight: 0,
                  ),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _urlCtl,
                    builder: (context, value, _) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (value.text.isNotEmpty)
                            _smallIconButton(
                              Icons.close,
                              '주소 모두 지우기',
                              _downloading ? null : _clearUrl,
                            ),
                          _smallIconButton(
                            Icons.content_paste,
                            '붙여넣기',
                            _downloading ? null : _paste,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                onSubmitted: (_) => _fetch(),
              ),
            ),
            const SizedBox(width: 8),
            PillButton(
              onPressed: _downloading ? null : _fetch,
              tooltip: '조회',
              icon: const Icon(Icons.search, size: 20),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoCard(MediaInfo info, bool wide, {bool loading = false}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // 그림이 아직 없거나 오는 중일 때는 검은색 · 회색 사선 무늬(로딩 중 표시).
    const stripes = LoadingStripes();
    final failed = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: colors.primary),
    );
    final thumbnail = AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (info.thumbnail == null)
            (loading ? stripes : failed)
          else
            Image.network(
              info.thumbnail!,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : stripes,
              errorBuilder: (_, _, _) => failed,
            ),
          if (info.durationSeconds > 0)
            Positioned(
              right: 5,
              bottom: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE621192F),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: Text(
                    formatSeconds(info.durationSeconds),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final details = Padding(
      padding: EdgeInsets.all(wide ? 15 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YouTube',
            style: theme.textTheme.labelSmall?.copyWith(color: colors.primary),
          ),
          const SizedBox(height: 3),
          Text(
            info.title,
            maxLines: wide ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style:
                (wide ? theme.textTheme.titleLarge : theme.textTheme.titleSmall)
                    ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (info.uploader.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              info.uploader,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [thumbnail, details],
            )
          : Padding(
              padding: const EdgeInsets.all(7),
              child: Row(
                children: [
                  SizedBox(
                    width: 105,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: thumbnail,
                    ),
                  ),
                  Expanded(child: details),
                ],
              ),
            ),
    );
  }

  Widget _buildOptions(MediaInfo info, {bool loading = false}) {
    final busy = _downloading;
    final canTrim = info.durationSeconds > 1;
    final trimmed = _trimOn && canTrim;
    final fraction = _selectedFraction(info);
    String? size(int? bytes) => loading
        ? '약 ??'
        : bytes == null
        ? null
        : '약 ${formatBytes(bytes)}';
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sectionDivider = Border(
      top: BorderSide(color: colors.outlineVariant),
    );
    // 조회 중에는 값이 필요한 조작부만 흐리게 하고 누를 수 없게 한다(펼치기 줄은 눌러도 된다).
    Widget dim(Widget w) =>
        loading ? IgnorePointer(child: Opacity(opacity: .45, child: w)) : w;
    final card = Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '저장 옵션',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            dim(
              SegmentedButton<MediaKind>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  backgroundColor: colors.surfaceContainerHighest,
                  selectedBackgroundColor: colors.secondaryContainer,
                  selectedForegroundColor: colors.primary,
                  side: BorderSide(color: colors.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: MediaKind.audio,
                    icon: Icon(Icons.headphones, size: 17),
                    label: Text('음원'),
                  ),
                  ButtonSegment(
                    value: MediaKind.video,
                    icon: Icon(Icons.movie_outlined, size: 17),
                    label: Text('영상'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: busy
                    ? null
                    : (s) => setState(() => _kind = s.first),
              ),
            ),
            const SizedBox(height: 12),
            if (_kind == MediaKind.audio)
              dim(
                _formats<String>(
                  values: const {'mp3': 'MP3', 'm4a': 'M4A', 'opus': 'OPUS'},
                  sub: {
                    for (final f in const ['mp3', 'm4a', 'opus'])
                      f: size(estimateAudioBytes(info, f, fraction: fraction)),
                  },
                  selected: _audioFormat,
                  onSelected: (v) => setState(() => _audioFormat = v),
                  enabled: !busy,
                ),
              )
            else
              dim(
                _formats<int?>(
                  values: const {
                    null: '최고',
                    1080: '1080p',
                    720: '720p',
                    480: '480p',
                    360: '360p',
                  },
                  sub: {
                    for (final h in const <int?>[null, 1080, 720, 480, 360])
                      h: size(estimateVideoBytes(info, h, fraction: fraction)),
                  },
                  selected: _maxHeight,
                  onSelected: (v) => setState(() => _maxHeight = v),
                  enabled: !busy,
                ),
              ),
            const SizedBox(height: 10),
            ExpansionTile(
              // 접혀 있으면 처음부터 끝까지, 펼치면 구간만 저장한다(펼침 = 구간 자르기 켜짐).
              key: ValueKey('trim-${info.url}'),
              initiallyExpanded: _trimOn,
              enabled: (canTrim || loading) && !busy,
              onExpansionChanged: (open) {
                setState(() => _trimOn = open);
                // 구간 자르기를 펼치면 미리듣기에 쓸 소리를 미리 받아 둔다(너무 긴 영상은 제외).
                if (open && info.durationSeconds <= 1800) {
                  unawaited(
                    _preview.prefetch(info.url, audioUrl: info.previewAudioUrl),
                  );
                }
              },
              dense: true,
              tilePadding: EdgeInsets.zero,
              shape: sectionDivider,
              collapsedShape: sectionDivider,
              leading: Icon(Icons.content_cut, size: 17, color: colors.primary),
              title: const Text('구간 자르기'),
              subtitle: loading
                  ? const Text('길이를 알아오는 중… (??)')
                  : !canTrim
                  ? const Text('길이를 알 수 없는 영상은 자를 수 없습니다.')
                  : trimmed
                  ? Text(
                      '${formatSeconds(_trimStart)}–${formatSeconds(_trimEnd)}',
                    )
                  : const Text('필요한 부분만 저장하려면 펼치세요'),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                if (loading)
                  IgnorePointer(
                    child: Opacity(
                      opacity: .45,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [TrimSelectorSkeleton(), RangePreviewSkeleton()],
                        ),
                      ),
                    ),
                  ),
                if (trimmed)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TrimSelector(
                          duration: info.durationSeconds,
                          start: _trimStart,
                          end: _trimEnd,
                          enabled: !busy,
                          onChanged: (s, e) => setState(() {
                            _trimStart = s;
                            _trimEnd = e;
                          }),
                        ),
                        RangePreview(
                          // 다른 영상을 조회하면 미리듣기 플레이어도 새로 만든다.
                          key: ValueKey(info.url),
                          start: _trimStart,
                          end: _trimEnd,
                          storyboard: info.storyboard,
                          render: (s, e) => _preview.render(
                            info.url,
                            s,
                            e,
                            _gain,
                            audioUrl: info.previewAudioUrl,
                          ),
                          enabled: !busy,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (_kind == MediaKind.audio)
              ExpansionTile(
                initiallyExpanded: false,
                maintainState: true,
                dense: true,
                tilePadding: EdgeInsets.zero,
                shape: sectionDivider,
                collapsedShape: sectionDivider,
                leading: Icon(
                  Icons.volume_up_outlined,
                  size: 17,
                  color: colors.primary,
                ),
                title: const Text('음량 조절'),
                childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                children: [
                  dim(
                    GainSelector(
                      value: _gain,
                      enabled: !busy,
                      onPreview: () {
                        // 음량을 비교해 듣기 좋게, 선택한 곳(또는 곡 앞쪽 30% 지점)에서 15초만 들려 준다.
                        final s0 = trimmed ? _trimStart : 0;
                        final e0 = trimmed ? _trimEnd : info.durationSeconds;
                        final s1 = e0 - s0 > 30
                            ? s0 + ((e0 - s0) * 0.3).floor()
                            : s0;
                        final e1 = e0 - s1 > 15 ? s1 + 15 : e0;
                        return _preview.render(
                          info.url,
                          s1,
                          e1,
                          _gain,
                          audioUrl: info.previewAudioUrl,
                        );
                      },
                      analysisSource: (
                        info.url,
                        trimmed ? _trimStart : null,
                        trimmed ? _trimEnd : null,
                      ),
                      onAuto: (token) async {
                        // 소리를 한 번에 받아 두면(보통 1초 안팎) yt-dlp 로 다시 받는 것보다 분석이 훨씬 빠르다.
                        // 너무 긴 영상은 전체를 받는 게 낭비라 기존 방식(필요한 구간만 yt-dlp 로)을 쓴다.
                        if (info.durationSeconds <= 1800) {
                          await _preview.prefetch(
                            info.url,
                            audioUrl: info.previewAudioUrl,
                          );
                        }
                        return _b.measureGain(
                          info.url,
                          token,
                          remote: true,
                          startSec: trimmed ? _trimStart.toDouble() : null,
                          endSec: trimmed ? _trimEnd.toDouble() : null,
                        );
                      },
                      onChanged: (g) => setState(() => _gain = g),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
    return card;
  }

  double _selectedFraction(MediaInfo info) =>
      _trimOn && info.durationSeconds > 1
      ? (_trimEnd - _trimStart) / info.durationSeconds
      : 1.0;

  Widget _formats<T>({
    required Map<T, String> values,
    required T selected,
    required void Function(T) onSelected,
    required bool enabled,
    Map<T, String?>? sub,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        const spacing = 7.0;
        final columns = box.maxWidth >= 195 ? 3 : 2;
        final width = (box.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final e in values.entries)
              SizedBox(
                width: width,
                child: Semantics(
                  button: true,
                  selected: e.key == selected,
                  child: Material(
                    color: e.key == selected
                        ? colors.secondaryContainer
                        : colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                      side: BorderSide(
                        color: e.key == selected
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: enabled ? () => onSelected(e.key) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.value,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: e.key == selected
                                    ? colors.primary
                                    : colors.onSurface,
                              ),
                            ),
                            Text(
                              sub?[e.key] ?? '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActionArea() {
    final p = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_downloading) ...[
          LinearProgressIndicator(value: p?.percent),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  p == null
                      ? ''
                      : p.percent != null
                      ? '${p.stage} ${(p.percent! * 100).toStringAsFixed(0)}%'
                      : p.stage,
                ),
              ),
              TextButton(
                onPressed: () => _token?.cancel(),
                child: const Text('취소'),
              ),
            ],
          ),
        ],
        if (_dlError != null) _errorText(_dlError!),
        if (_result != null) _buildResult(_result!),
        if (_saved != null && !_downloading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PillButton(
              onPressed: () => widget.editController.open(_saved!),
              icon: const Icon(Icons.content_cut),
              label: const Text('편집하기 (듣고 구간 자르기)'),
            ),
          ),
        if (_savedVideo != null && !_downloading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PillButton(
              onPressed: () => widget.videoController.open(_savedVideo!),
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('영상 편집하기 (보면서 구간 자르기)'),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(bool wide, double gutter) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final info = _info;
    final trimmed = _trimOn && info != null && info.durationSeconds > 1;
    final bytes = info == null
        ? null
        : _kind == MediaKind.audio
        ? estimateAudioBytes(
            info,
            _audioFormat,
            fraction: _selectedFraction(info),
          )
        : estimateVideoBytes(
            info,
            _maxHeight,
            fraction: _selectedFraction(info),
          );
    final format = _kind == MediaKind.audio
        ? _audioFormat.toUpperCase()
        : 'MP4 ${_maxHeight == null ? '최고' : '${_maxHeight}p'}';
    final button = FilledButton.icon(
      onPressed: info == null || _downloading || _fetching ? null : _download,
      icon: const Icon(Icons.download, size: 19),
      label: Text(
        _downloading
            ? '다운로드 중…'
            : trimmed
            ? '구간 다운로드'
            : '다운로드',
      ),
    );
    final loading = info == null && _fetching;
    final summary = (info == null && !loading)
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: wide
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                loading
                    ? '$format · 약 ??'
                    : bytes == null
                    ? format
                    : '$format · 약 ${formatBytes(bytes)}',
                maxLines: 2,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (info == null)
                Text('길이 ??', style: theme.textTheme.labelSmall)
              else if (info.durationSeconds > 0)
                Text(
                  trimmed
                      ? '선택 구간 · ${formatSeconds(_trimEnd - _trimStart)}'
                      : '전체 길이 · ${formatSeconds(info.durationSeconds)}',
                  style: theme.textTheme.labelSmall,
                ),
            ],
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_downloading || _result != null || _dlError != null) ...[
                    _buildActionArea(),
                    const SizedBox(height: 10),
                  ],
                  if (wide)
                    Row(
                      children: [
                        Expanded(child: _buildSaveLocation()),
                        if (summary != null) ...[
                          const SizedBox(width: 12),
                          Flexible(child: summary),
                        ],
                        const SizedBox(width: 12),
                        button,
                      ],
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSaveLocation(),
                        const SizedBox(height: 8),
                        if (summary == null)
                          button
                        else
                          Row(
                            children: [
                              Expanded(child: summary),
                              const SizedBox(width: 8),
                              button,
                            ],
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(DownloadResult r) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.check_circle),
        title: const Text('저장 완료'),
        subtitle: Tooltip(
          message: r.location,
          child: SelectableText(r.location, maxLines: 2),
        ),
        trailing: (!_b.canReveal || r.filePath == null)
            ? null
            : TextButton(
                onPressed: () => _b.reveal(r),
                child: const Text('폴더 열기'),
              ),
      ),
    );
  }

  Widget _buildSaveLocation() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder_outlined, size: 18, color: colors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '저장 위치',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                _b.saveLocationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        if (_b.canChooseFolder)
          TextButton(
            onPressed: _downloading
                ? null
                : () async {
                    await _b.chooseFolder();
                    if (mounted) setState(() {});
                  },
            child: const Text('변경'),
          ),
      ],
    );
  }

  Widget _errorText(String text) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
