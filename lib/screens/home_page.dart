import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../util/names.dart';
import '../state/app_state.dart';
import '../util/size_estimate.dart';
import '../util/time_format.dart';
import '../widgets/gain_selector.dart';
import '../widgets/trim_selector.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.backend,
    required this.recent,
    required this.editController,
  });

  final Backend backend;

  /// 받은 음원을 최근 목록에 올리고, "편집하기"로 편집 탭에 넘기는 데 쓴다.
  final RecentStore recent;
  final EditController editController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Backend get _b => widget.backend;
  final _urlCtl = TextEditingController();

  // 엔진 준비
  bool _ready = false;
  String _setupMsg = '준비 중…';
  double? _setupProgress;
  String? _setupError;

  // 영상 정보
  MediaInfo? _info;
  bool _fetching = false;
  String? _fetchError;

  // 옵션
  MediaKind _kind = MediaKind.audio;
  String _audioFormat = 'mp3';
  AudioGain _gain = const AudioGain.none();
  int? _maxHeight = 1080;
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

  static final _urlRe = RegExp(r'https?://[^\s]+');

  @override
  void initState() {
    super.initState();
    _b.onSharedText = _acceptUrl;
    _setup();
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    super.dispose();
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
      if (shared != null) _acceptUrl(shared);
    } catch (e) {
      if (mounted) setState(() => _setupError = _msg(e));
    }
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// 공유로 받은 텍스트나 붙여넣은 글에서 URL만 뽑아 바로 조회한다.
  void _acceptUrl(String text) {
    final m = _urlRe.firstMatch(text);
    _urlCtl.text = m?.group(0) ?? text.trim();
    _fetch();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _acceptUrl(data!.text!);
  }

  Future<void> _fetch() async {
    final raw = _urlCtl.text.trim();
    final url = _urlRe.firstMatch(raw)?.group(0);
    if (url == null) {
      setState(() => _fetchError = '올바른 링크(https://…)를 입력해 주세요.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _fetching = true;
      _fetchError = null;
      _info = null;
      _result = null;
      _dlError = null;
      _saved = null;
    });
    try {
      final info = await _b.fetchInfo(url);
      if (!mounted) return;
      setState(() {
        _info = info;
        _trimStart = 0;
        _trimEnd = info.durationSeconds;
        _trimOn = false;
      });
    } catch (e) {
      if (mounted) setState(() => _fetchError = _msg(e));
    } finally {
      if (mounted) setState(() => _fetching = false);
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
    });
    try {
      final options = DownloadOptions(
        kind: _kind,
        audioFormat: _audioFormat,
        maxHeight: _maxHeight,
        trimStart: trim ? _trimStart : null,
        trimEnd: trim ? _trimEnd : null,
        gain: _kind == MediaKind.audio ? _gain : const AudioGain.none(),
      );
      final r = await _b.download(
        info.url,
        options,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        token,
      );
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
      });
      if (_saved != null) widget.recent.add(_saved!);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('YTDL'),
        actions: [
          if (_ready)
            IconButton(
              tooltip: '다운로드 엔진 업데이트 (유튜브가 안 받아질 때)',
              icon: const Icon(Icons.system_update_alt),
              onPressed: _downloading ? null : _updateEngine,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: !_ready ? _buildSetup() : _buildMain(context),
          ),
        ),
      ),
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

  Widget _buildMain(BuildContext context) {
    final info = _info;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildUrlRow(),
        if (_fetchError != null) _errorText(_fetchError!),
        if (_fetching)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
        if (info != null) ...[
          const SizedBox(height: 16),
          _buildInfoCard(info),
          const SizedBox(height: 16),
          _buildOptions(info),
          const SizedBox(height: 16),
          _buildActionArea(),
        ],
        const SizedBox(height: 24),
        _buildSaveLocation(),
      ],
    );
  }

  Widget _buildUrlRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlCtl,
            enabled: !_downloading,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              labelText: '유튜브 링크',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '붙여넣기',
                icon: const Icon(Icons.content_paste),
                onPressed: _downloading ? null : _paste,
              ),
            ),
            onSubmitted: (_) => _fetch(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: (_fetching || _downloading) ? null : _fetch,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Text('조회'),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(MediaInfo info) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info.thumbnail != null)
            SizedBox(
              width: 140,
              height: 100,
              child: Image.network(
                info.thumbnail!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Colors.black12,
                  child: Icon(Icons.music_video),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (info.uploader.isNotEmpty) info.uploader,
                      if (info.durationSeconds > 0) formatSeconds(info.durationSeconds),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(MediaInfo info) {
    final busy = _downloading;
    final canTrim = info.durationSeconds > 1;
    // 구간 자르기를 켰으면 자를 길이 비율만큼 용량도 줄여서 보여 준다.
    final trimmed = _trimOn && canTrim;
    final fraction = trimmed ? (_trimEnd - _trimStart) / info.durationSeconds : 1.0;
    String? size(int? bytes) => bytes == null ? null : '약 ${formatBytes(bytes)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<MediaKind>(
          segments: const [
            ButtonSegment(value: MediaKind.audio, icon: Icon(Icons.music_note), label: Text('음원')),
            ButtonSegment(value: MediaKind.video, icon: Icon(Icons.movie), label: Text('영상')),
          ],
          selected: {_kind},
          onSelectionChanged: busy ? null : (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 12),
        if (_kind == MediaKind.audio)
          _chips<String>(
            label: '형식',
            values: const {'mp3': 'MP3', 'm4a': 'M4A (AAC)', 'opus': 'OPUS'},
            sub: {
              for (final f in const ['mp3', 'm4a', 'opus'])
                f: size(estimateAudioBytes(info, f, fraction: fraction)),
            },
            selected: _audioFormat,
            onSelected: (v) => setState(() => _audioFormat = v),
            enabled: !busy,
          )
        else
          _chips<int?>(
            label: '화질',
            values: const {null: '최고', 1080: '1080p', 720: '720p', 480: '480p', 360: '360p'},
            sub: {
              for (final h in const <int?>[null, 1080, 720, 480, 360])
                h: size(estimateVideoBytes(info, h, fraction: fraction)),
            },
            selected: _maxHeight,
            onSelected: (v) => setState(() => _maxHeight = v),
            enabled: !busy,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            trimmed ? '용량은 자를 구간 기준의 예상치예요.' : '용량은 예상치라 실제와 조금 다를 수 있어요.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_kind == MediaKind.audio) ...[
          const SizedBox(height: 12),
          GainSelector(
            value: _gain,
            enabled: !busy,
            onChanged: (g) => setState(() => _gain = g),
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('필요한 구간만 잘라서 저장'),
          subtitle: canTrim ? null : const Text('길이를 알 수 없는 영상은 자를 수 없습니다.'),
          value: _trimOn && canTrim,
          onChanged: (busy || !canTrim) ? null : (v) => setState(() => _trimOn = v),
        ),
        if (_trimOn && canTrim)
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
      ],
    );
  }

  Widget _chips<T>({
    required String label,
    required Map<T, String> values,
    required T selected,
    required void Function(T) onSelected,
    required bool enabled,
    Map<T, String?>? sub,
  }) {
    final small = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        for (final e in values.entries)
          ChoiceChip(
            label: sub?[e.key] == null
                ? Text(e.value)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(e.value), Text(sub![e.key]!, style: small)],
                  ),
            selected: e.key == selected,
            onSelected: enabled ? (_) => onSelected(e.key) : null,
          ),
      ],
    );
  }

  Widget _buildActionArea() {
    final p = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_downloading)
          FilledButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('다운로드'),
            ),
          )
        else ...[
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
            child: FilledButton.tonalIcon(
              onPressed: () => widget.editController.open(_saved!),
              icon: const Icon(Icons.content_cut),
              label: const Text('편집하기 (듣고 구간 자르기)'),
            ),
          ),
      ],
    );
  }

  Widget _buildResult(DownloadResult r) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(top: 12),
      child: ListTile(
        leading: const Icon(Icons.check_circle),
        title: const Text('저장 완료'),
        subtitle: SelectableText(r.location),
        trailing: (!_b.canReveal || r.filePath == null)
            ? null
            : TextButton(onPressed: () => _b.reveal(r), child: const Text('폴더 열기')),
      ),
    );
  }

  Widget _buildSaveLocation() {
    return Row(
      children: [
        const Icon(Icons.folder_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _b.saveLocationLabel,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
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
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
}
