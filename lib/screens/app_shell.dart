import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../state/app_state.dart';
import 'edit_page.dart';
import 'home_page.dart';

/// 화면 폭에 맞춰 메뉴를 배치하고 두 탭의 상태를 유지한다.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.backend});

  final Backend backend;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final RecentStore _recent = RecentStore();
  final EditController _edit = EditController();
  int _index = 0;
  int _seenRequests = 0;

  @override
  void initState() {
    super.initState();
    _recent.load();
    _edit.addListener(_onEdit);
  }

  @override
  void dispose() {
    _edit.removeListener(_onEdit);
    _edit.dispose();
    _recent.dispose();
    super.dispose();
  }

  /// 다운로드 탭의 "편집하기" 등이 파일을 넘기면 편집 탭으로 이동한다.
  void _onEdit() {
    if (_edit.openRequests != _seenRequests) {
      _seenRequests = _edit.openRequests;
      if (mounted) setState(() => _index = 1);
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
        ),
        EditPage(
          backend: widget.backend,
          controller: _edit,
          recent: _recent,
          active: _index == 1,
        ),
      ],
    );
    const destinations = [
      NavigationDestination(icon: Icon(Icons.download_outlined), label: '다운로드'),
      NavigationDestination(icon: Icon(Icons.content_cut), label: '음원 편집'),
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
