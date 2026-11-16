import 'dart:io';

import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../state/app_state.dart';
import '../state/download_queue.dart';
import '../widgets/edit_media_icon.dart';
import 'edit_page.dart';
import '../state/settings.dart';
import 'home_page.dart';
import 'options_page.dart';
import 'queue_page.dart';
import 'video_edit_page.dart';

/// 화면 폭에 맞춰 메뉴를 배치하고 두 탭의 상태를 유지한다.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.backend});

  final Backend backend;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final RecentStore _recent = RecentStore();
  final RecentStore _videoRecent = RecentStore(key: 'recentVideo');
  final AppSettings _settings = AppSettings();
  final EditController _edit = EditController();
  final EditController _videoEdit = EditController();
  late final DownloadQueue _queue = DownloadQueue(
    widget.backend,
    // 폰은 한 번에 하나씩(배터리·발열), PC 는 둘씩 받아 yt-dlp 시작 시간을 겹친다.
    maxParallel: Platform.isAndroid ? 1 : 2,
    onDone: (item) {
      final saved = item.saved;
      if (saved == null) return;
      (item.isVideo ? _videoRecent : _recent).add(saved);
    },
  );

  // 탭 번호
  static const _tabHome = 0;
  static const _tabQueue = 1;
  static const _tabAudio = 2;
  static const _tabVideo = 3;
  static const _tabOptions = 4;

  int _index = _tabHome;
  int _seenRequests = 0;
  int _seenVideoRequests = 0;

  @override
  void initState() {
    super.initState();
    _recent.load();
    _videoRecent.load();
    _settings.load();
    _edit.addListener(_onEdit);
    _videoEdit.addListener(_onVideoEdit);
  }

  @override
  void dispose() {
    _edit.removeListener(_onEdit);
    _videoEdit.removeListener(_onVideoEdit);
    _edit.dispose();
    _videoEdit.dispose();
    _queue.dispose();
    _recent.dispose();
    _videoRecent.dispose();
    _settings.dispose();
    super.dispose();
  }

  /// 다운로드 탭의 "편집하기" 등이 파일을 넘기면 편집 탭으로 이동한다.
  void _onEdit() {
    if (_edit.openRequests != _seenRequests) {
      _seenRequests = _edit.openRequests;
      if (mounted) setState(() => _index = _tabAudio);
    }
  }

  /// 다운로드 탭의 "영상 편집" 버튼이 파일을 넘기면 영상 편집 탭으로 이동한다.
  void _onVideoEdit() {
    if (_videoEdit.openRequests != _seenVideoRequests) {
      _seenVideoRequests = _videoEdit.openRequests;
      if (mounted) setState(() => _index = _tabVideo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final scheme = Theme.of(context).colorScheme;
    final body = IndexedStack(
      index: _index,
      children: [
        HomePage(
          backend: widget.backend,
          recent: _recent,
          editController: _edit,
          videoController: _videoEdit,
          videoRecent: _videoRecent,
          settings: _settings,
          queue: _queue,
          onOpenQueue: () => setState(() => _index = _tabQueue),
        ),
        QueuePage(
          queue: _queue,
          backend: widget.backend,
          audioController: _edit,
          videoController: _videoEdit,
        ),
        EditPage(
          backend: widget.backend,
          controller: _edit,
          recent: _recent,
          active: _index == _tabAudio,
        ),
        VideoEditPage(
          backend: widget.backend,
          controller: _videoEdit,
          recent: _videoRecent,
          settings: _settings,
          active: _index == _tabVideo,
        ),
        // 탭에 들어올 때마다 새로 그려서 저장 위치 같은 값이 최신으로 보이게 한다.
        OptionsPage(
          key: ValueKey(_index == _tabOptions),
          backend: widget.backend,
          settings: _settings,
        ),
      ],
    );
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.download_outlined),
        label: '다운로드',
      ),
      NavigationDestination(
        icon: _QueueIcon(queue: _queue),
        label: '대기열',
      ),
      const NavigationDestination(
        icon: EditMediaIcon.audio(),
        label: '음원 편집',
      ),
      const NavigationDestination(
        icon: EditMediaIcon.video(),
        label: '영상 편집',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        label: '옵션',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Flex(
          direction: wide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: const Color(0xFF21192F),
              child: SizedBox(
                width: wide ? 172 : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 12 : 16,
                    vertical: wide ? 24 : 11,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Image(
                              image: AssetImage('assets/icon/icon.png'),
                              width: 34,
                              height: 34,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'YTDL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wide) ...[
                        const SizedBox(height: 28),
                        for (var i = 0; i < destinations.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: TextButton.icon(
                              onPressed: () => setState(() => _index = i),
                              style: TextButton.styleFrom(
                                foregroundColor: i == _index
                                    ? Colors.white
                                    : const Color(0xFFC0B3D4),
                                backgroundColor: i == _index
                                    ? const Color(0xFF47345E)
                                    : null,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                              icon: destinations[i].icon,
                              label: Text(destinations[i].label),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              height: 62,
              backgroundColor: scheme.surface,
              indicatorColor: scheme.secondaryContainer,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: destinations,
            ),
    );
  }
}

/// 대기열 탭 아이콘. 남은 항목 수를 작은 배지로 보여 준다.
class _QueueIcon extends StatelessWidget {
  const _QueueIcon({required this.queue});

  final DownloadQueue queue;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final n = queue.activeCount;
        return Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: const Icon(Icons.queue_music),
        );
      },
    );
  }
}
