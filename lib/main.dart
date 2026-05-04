import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_controller.dart';
import 'models.dart';

void main() {
  MediaKit.ensureInitialized();
  runApp(const VideoPartyApp());
}

class VideoPartyApp extends StatefulWidget {
  const VideoPartyApp({super.key});

  @override
  State<VideoPartyApp> createState() => _VideoPartyAppState();
}

class _VideoPartyAppState extends State<VideoPartyApp> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Video Party P2P',
          debugShowCheckedModeBanner: false,
          themeMode: switch (controller.visualTheme) {
            AppVisualTheme.standard => ThemeMode.dark,
            AppVisualTheme.light => ThemeMode.light,
            AppVisualTheme.system => ThemeMode.system,
          },
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: PartyHomePage(controller: controller),
        );
      },
    );
  }
}

class PartyHomePage extends StatefulWidget {
  const PartyHomePage({required this.controller, super.key});

  final AppController controller;

  @override
  State<PartyHomePage> createState() => _PartyHomePageState();
}

enum _SidebarSection { home, playlist, downloads, settings }

class _PartyHomePageState extends State<PartyHomePage> {
  AppController get controller => widget.controller;

  _SidebarSection _selectedSection = _SidebarSection.home;

  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _rightPanelScrollController = ScrollController();
  final GlobalKey _homeKey = GlobalKey();
  final GlobalKey _controlKey = GlobalKey();
  final GlobalKey _playerKey = GlobalKey();
  final GlobalKey _libraryKey = GlobalKey();
  final GlobalKey _playlistKey = GlobalKey();
  final GlobalKey _peersKey = GlobalKey();
  final GlobalKey _eventsKey = GlobalKey();

  late final TextEditingController peerName;
  late final TextEditingController trackerHost;
  late final TextEditingController trackerPort;
  late final TextEditingController advertisedHost;
  late final TextEditingController uploadPort;
  late final TextEditingController folderPath;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    peerName = TextEditingController(text: controller.peerName);
    trackerHost = TextEditingController(text: controller.trackerHost);
    trackerPort = TextEditingController(text: '${controller.trackerPort}');
    advertisedHost = TextEditingController(text: controller.advertisedHost);
    uploadPort = TextEditingController(text: '${controller.uploadPort}');
    folderPath = TextEditingController();
  }

  @override
  void dispose() {
    _mainScrollController.dispose();
    _rightPanelScrollController.dispose();
    peerName.dispose();
    trackerHost.dispose();
    trackerPort.dispose();
    advertisedHost.dispose();
    uploadPort.dispose();
    folderPath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                final content = wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SideBar(
                            controller: controller,
                            selectedSection: _selectedSection,
                            onHome: () =>
                                _navigateTo(_SidebarSection.home, _homeKey),
                            onPlaylist: () => _navigateTo(
                              _SidebarSection.playlist,
                              _playlistKey,
                            ),
                            onDownloads: () => _navigateTo(
                              _SidebarSection.downloads,
                              _playerKey,
                            ),
                            onSettings: () => _navigateTo(
                              _SidebarSection.settings,
                              _controlKey,
                            ),
                          ),
                          Expanded(
                            child: _MainArea(
                              scrollController: _mainScrollController,
                              controller: controller,
                              peerName: peerName,
                              trackerHost: trackerHost,
                              trackerPort: trackerPort,
                              advertisedHost: advertisedHost,
                              uploadPort: uploadPort,
                              folderPath: folderPath,
                              homeKey: _homeKey,
                              controlKey: _controlKey,
                              playerKey: _playerKey,
                              libraryKey: _libraryKey,
                            ),
                          ),
                          SizedBox(
                            width: 360,
                            child: _RightPanel(
                              controller: controller,
                              scrollController: _rightPanelScrollController,
                              playlistKey: _playlistKey,
                              peersKey: _peersKey,
                              eventsKey: _eventsKey,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _Header(key: _homeKey, controller: controller),
                          const SizedBox(height: 16),
                          _ControlPanel(
                            key: _controlKey,
                            controller: controller,
                            peerName: peerName,
                            trackerHost: trackerHost,
                            trackerPort: trackerPort,
                            advertisedHost: advertisedHost,
                            uploadPort: uploadPort,
                            folderPath: folderPath,
                          ),
                          const SizedBox(height: 16),
                          _NowPlaying(key: _playerKey, controller: controller),
                          const SizedBox(height: 16),
                          _Library(key: _libraryKey, controller: controller),
                          const SizedBox(height: 16),
                          _RightPanel(
                            controller: controller,
                            playlistKey: _playlistKey,
                            peersKey: _peersKey,
                            eventsKey: _eventsKey,
                          ),
                        ],
                      );
                return wide
                    ? content
                    : ColoredBox(color: context.appBackground, child: content);
              },
            ),
          ),
        );
      },
    );
  }

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: 0.04,
    );
  }

  void _navigateTo(_SidebarSection section, GlobalKey key) {
    setState(() {
      _selectedSection = section;
    });
    _scrollTo(key);
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff00c2a8),
    brightness: brightness,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xff101114)
        : const Color(0xfff6f9fb),
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

extension PartyPalette on BuildContext {
  bool get isPartyDark => Theme.of(this).brightness == Brightness.dark;

  Color get appBackground =>
      isPartyDark ? const Color(0xff101114) : const Color(0xfff6f9fb);
  Color get sidebarBackground =>
      isPartyDark ? const Color(0xff181a1f) : const Color(0xffe8f1f4);
  Color get panelBackground =>
      isPartyDark ? const Color(0xff15171b) : const Color(0xffedf4f7);
  Color get cardBackground =>
      isPartyDark ? const Color(0xff181a1f) : const Color(0xffffffff);
  Color get raisedBackground =>
      isPartyDark ? const Color(0xff1b1d22) : const Color(0xffffffff);
  Color get fieldBackground =>
      isPartyDark ? const Color(0xff101114) : const Color(0xfff7fafb);
  Color get mediaBackground =>
      isPartyDark ? const Color(0xff090a0c) : const Color(0xffdce8ed);
  Color get mediaStripe =>
      isPartyDark ? const Color(0xff15181c) : const Color(0xffc5d4da);
  Color get tileBackground =>
      isPartyDark ? const Color(0xff24272e) : const Color(0xffeef5f7);
  Color get rowBackground =>
      isPartyDark ? const Color(0xff1c1f24) : const Color(0xffffffff);
  Color get selectedRowBackground =>
      isPartyDark ? const Color(0xff20342f) : const Color(0xffd9f5ee);
  Color get borderColor =>
      isPartyDark ? Colors.white10 : const Color(0xffd5e1e6);
  Color get borderStrongColor =>
      isPartyDark ? Colors.white12 : const Color(0xffb9cbd2);
  Color get primaryAccent =>
      isPartyDark ? const Color(0xff00c2a8) : const Color(0xff008f7d);
  Color get primaryAccentSoft =>
      isPartyDark ? const Color(0xff38e8c6) : const Color(0xff00776a);
  Color get warningAccent =>
      isPartyDark ? const Color(0xffffbd59) : const Color(0xffb86f00);
  Color get secondaryAccent =>
      isPartyDark ? const Color(0xff00a3ff) : const Color(0xff0877bd);
  Color get textMuted => isPartyDark ? Colors.white60 : const Color(0xff4e5c66);
  Color get textSubtle =>
      isPartyDark ? Colors.white54 : const Color(0xff6f7d86);
  Color get textFaint => isPartyDark ? Colors.white38 : const Color(0xff9aa8af);
  Color get navSelected =>
      isPartyDark ? const Color(0xff25322f) : const Color(0xffccefe7);
  Color get statusActiveBackground =>
      isPartyDark ? const Color(0xff183a32) : const Color(0xffd8f4ed);
  Color get statusInactiveBackground =>
      isPartyDark ? const Color(0xff25272d) : const Color(0xfff5f8fa);
}

class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.controller,
    required this.selectedSection,
    required this.onHome,
    required this.onPlaylist,
    required this.onDownloads,
    required this.onSettings,
  });

  final AppController controller;
  final _SidebarSection selectedSection;
  final VoidCallback onHome;
  final VoidCallback onPlaylist;
  final VoidCallback onDownloads;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      color: context.sidebarBackground,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Icon(
            Icons.movie_filter_rounded,
            color: context.primaryAccent,
            size: 34,
          ),
          const SizedBox(height: 28),
          _NavIcon(
            icon: Icons.home_rounded,
            tooltip: 'Inicio',
            selected: selectedSection == _SidebarSection.home,
            onPressed: onHome,
          ),
          _NavIcon(
            icon: Icons.queue_music_rounded,
            tooltip: 'Playlist',
            selected: selectedSection == _SidebarSection.playlist,
            onPressed: onPlaylist,
          ),
          _NavIcon(
            icon: Icons.cloud_download_rounded,
            tooltip: 'Player e downloads',
            selected: selectedSection == _SidebarSection.downloads,
            onPressed: onDownloads,
          ),
          _NavIcon(
            icon: Icons.settings_rounded,
            tooltip: 'Configuracoes',
            selected: selectedSection == _SidebarSection.settings,
            onPressed: onSettings,
          ),
          const Spacer(),
          _ThemeMenu(controller: controller),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: selected ? context.navSelected : Colors.transparent,
          fixedSize: const Size(48, 48),
        ),
        icon: Icon(
          icon,
          color: selected ? context.primaryAccent : context.textSubtle,
        ),
      ),
    );
  }
}

class _MainArea extends StatelessWidget {
  const _MainArea({
    required this.scrollController,
    required this.controller,
    required this.peerName,
    required this.trackerHost,
    required this.trackerPort,
    required this.advertisedHost,
    required this.uploadPort,
    required this.folderPath,
    required this.homeKey,
    required this.controlKey,
    required this.playerKey,
    required this.libraryKey,
  });

  final ScrollController scrollController;
  final AppController controller;
  final TextEditingController peerName;
  final TextEditingController trackerHost;
  final TextEditingController trackerPort;
  final TextEditingController advertisedHost;
  final TextEditingController uploadPort;
  final TextEditingController folderPath;
  final GlobalKey homeKey;
  final GlobalKey controlKey;
  final GlobalKey playerKey;
  final GlobalKey libraryKey;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(22),
      children: [
        _Header(key: homeKey, controller: controller),
        const SizedBox(height: 16),
        _ControlPanel(
          key: controlKey,
          controller: controller,
          peerName: peerName,
          trackerHost: trackerHost,
          trackerPort: trackerPort,
          advertisedHost: advertisedHost,
          uploadPort: uploadPort,
          folderPath: folderPath,
        ),
        const SizedBox(height: 18),
        _NowPlaying(key: playerKey, controller: controller),
        const SizedBox(height: 18),
        _Library(key: libraryKey, controller: controller),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Video Party P2P',
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Playlist colaborativa com tracker hibrido, peers TCP e prefetch.',
          style: TextStyle(color: context.textMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatusChip(
              icon: Icons.hub_rounded,
              label: controller.trackerRunning
                  ? 'Tracker ativo'
                  : 'Tracker remoto',
              active: controller.trackerRunning,
            ),
            _StatusChip(
              icon: Icons.upload_rounded,
              label: controller.peerServing ? 'Upload ativo' : 'Upload parado',
              active: controller.peerServing,
            ),
            const _StatusChip(
              icon: Icons.dashboard_customize_rounded,
              label: 'GUI ativa',
              active: true,
            ),
            const _StatusChip(
              icon: Icons.call_split_rounded,
              label: 'Paralelo',
              active: true,
            ),
            const _StatusChip(
              icon: Icons.lock_rounded,
              label: 'Cifrado',
              active: true,
            ),
            const _StatusChip(
              icon: Icons.route_rounded,
              label: 'Relay NAT',
              active: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? context.statusActiveBackground
            : context.statusInactiveBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? context.primaryAccentSoft : context.textSubtle,
          ),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.controller,
    required this.peerName,
    required this.trackerHost,
    required this.trackerPort,
    required this.advertisedHost,
    required this.uploadPort,
    required this.folderPath,
    super.key,
  });

  final AppController controller;
  final TextEditingController peerName;
  final TextEditingController trackerHost;
  final TextEditingController trackerPort;
  final TextEditingController advertisedHost;
  final TextEditingController uploadPort;
  final TextEditingController folderPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Field(label: 'Nome do peer', controller: peerName, width: 170),
              _Field(label: 'Tracker IP', controller: trackerHost, width: 150),
              _Field(
                label: 'Tracker porta',
                controller: trackerPort,
                width: 120,
              ),
              _Field(
                label: 'Meu IP/Tailscale',
                controller: advertisedHost,
                width: 160,
              ),
              _Field(label: 'Porta upload', controller: uploadPort, width: 120),
              _Field(
                label: 'Pasta de videos',
                controller: folderPath,
                width: 280,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _run(context, () async {
                  _saveConfig();
                  await controller.startTracker();
                }),
                icon: const Icon(Icons.hub_rounded),
                label: const Text('Iniciar tracker'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _run(context, () async {
                  _saveConfig();
                  await controller.startPeerServer();
                }),
                icon: const Icon(Icons.upload_rounded),
                label: const Text('Ativar upload'),
              ),
              OutlinedButton.icon(
                onPressed: () => _run(context, () async {
                  _saveConfig();
                  await controller.scanAndRegister();
                }),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Escanear e registrar'),
              ),
              OutlinedButton.icon(
                onPressed: () => _run(context, () async {
                  _saveConfig();
                  await controller.refresh();
                }),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Atualizar rede'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _saveConfig() {
    controller.updateConfig(
      peerName: peerName.text,
      trackerHost: trackerHost.text,
      trackerPort: int.tryParse(trackerPort.text) ?? controller.trackerPort,
      advertisedHost: advertisedHost.text,
      uploadPort: int.tryParse(uploadPort.text) ?? controller.uploadPort,
      folderPath: folderPath.text,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.width,
  });

  final String label;
  final TextEditingController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: context.fieldBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _ThemeMenu extends StatelessWidget {
  const _ThemeMenu({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final icon = switch (controller.visualTheme) {
      AppVisualTheme.standard => Icons.dark_mode_rounded,
      AppVisualTheme.light => Icons.light_mode_rounded,
      AppVisualTheme.system => Icons.brightness_auto_rounded,
    };
    return PopupMenuButton<AppVisualTheme>(
      tooltip: 'Tema',
      initialValue: controller.visualTheme,
      onSelected: controller.updateVisualTheme,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: AppVisualTheme.standard,
          child: ListTile(
            leading: Icon(Icons.dark_mode_rounded),
            title: Text('Padrao'),
          ),
        ),
        PopupMenuItem(
          value: AppVisualTheme.light,
          child: ListTile(
            leading: Icon(Icons.light_mode_rounded),
            title: Text('Branco'),
          ),
        ),
        PopupMenuItem(
          value: AppVisualTheme.system,
          child: ListTile(
            leading: Icon(Icons.brightness_auto_rounded),
            title: Text('Sistema'),
          ),
        ),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: context.statusInactiveBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.borderColor),
        ),
        child: Icon(icon, color: context.primaryAccent),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entry = controller.nowPlaying;
    final videoController = controller.videoController;
    final progress = controller.playbackDuration == 0
        ? 0.0
        : (controller.playbackSeconds / controller.playbackDuration).clamp(
            0.0,
            1.0,
          );
    return Container(
      constraints: const BoxConstraints(minHeight: 280),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.raisedBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 6.7,
            child: Container(
              decoration: BoxDecoration(
                color: context.mediaBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.borderStrongColor),
              ),
              child: Stack(
                children: [
                  if (videoController != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Video(controller: videoController),
                      ),
                    ),
                  if (entry == null || videoController == null) ...[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PlayerBackdropPainter(
                          stripeColor: context.mediaStripe,
                          accentColor: context.primaryAccent,
                        ),
                      ),
                    ),
                    Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        size: 76,
                        color: context.primaryAccent,
                      ),
                    ),
                  ],
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry?.title ?? 'Nenhum video em reproducao',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          color: context.primaryAccent,
                          backgroundColor: context.borderStrongColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.filled(
                tooltip: controller.isPlaying ? 'Pausar' : 'Tocar',
                onPressed: controller.togglePlayback,
                icon: Icon(
                  controller.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_clock(controller.playbackSeconds)} / ${_clock(controller.playbackDuration)}',
                style: TextStyle(color: context.textMuted),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  'Downloads: ${controller.downloadFolder}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textSubtle, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _clock(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }
}

class _PlayerBackdropPainter extends CustomPainter {
  const _PlayerBackdropPainter({
    required this.stripeColor,
    required this.accentColor,
  });

  final Color stripeColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = stripeColor;
    for (var i = 0; i < 10; i++) {
      final x = size.width * i / 9;
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), paint);
    }
    final accent = Paint()..color = accentColor.withValues(alpha: 0.14);
    canvas.drawCircle(
      Offset(size.width * .78, size.height * .18),
      size.width * .18,
      accent,
    );
    canvas.drawCircle(
      Offset(size.width * .2, size.height * .78),
      size.width * .13,
      accent,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayerBackdropPainter oldDelegate) {
    return oldDelegate.stripeColor != stripeColor ||
        oldDelegate.accentColor != accentColor;
  }
}

class _Library extends StatelessWidget {
  const _Library({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final videos = controller.snapshot.videos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Catalogo global',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (videos.isEmpty)
          const _EmptyState(
            icon: Icons.video_library_rounded,
            text: 'Atualize a rede ou registre uma pasta com videos.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 900
                  ? 4
                  : constraints.maxWidth > 660
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: videos.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.08,
                ),
                itemBuilder: (context, index) {
                  final video = videos[index];
                  final local =
                      controller.peer.localPathFor(video.hash) != null;
                  return _VideoTile(
                    video: video,
                    local: local,
                    onAdd: () =>
                        _run(context, () => controller.addToPlaylist(video)),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.video,
    required this.local,
    required this.onAdd,
  });

  final VideoItem video;
  final bool local;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: local ? context.primaryAccent : context.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.tileBackground,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Icon(
                  local
                      ? Icons.offline_pin_rounded
                      : Icons.movie_creation_rounded,
                  color: local ? context.primaryAccent : context.warningAccent,
                  size: 42,
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            video.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            formatBytes(video.size),
            style: TextStyle(color: context.textSubtle, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  local
                      ? 'local'
                      : '${video.hash.substring(0, video.hash.length < 8 ? video.hash.length : 8)}...',
                  style: TextStyle(color: context.textSubtle, fontSize: 12),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Adicionar a playlist',
                onPressed: onAdd,
                icon: const Icon(Icons.playlist_add_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.controller,
    this.scrollController,
    this.playlistKey,
    this.peersKey,
    this.eventsKey,
  });

  final AppController controller;
  final ScrollController? scrollController;
  final GlobalKey? playlistKey;
  final GlobalKey? peersKey;
  final GlobalKey? eventsKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.panelBackground,
      padding: const EdgeInsets.all(16),
      child: ListView(
        controller: scrollController,
        children: [
          _PanelTitle(
            key: playlistKey,
            icon: Icons.queue_music_rounded,
            title: 'Playlist global',
          ),
          const SizedBox(height: 10),
          if (controller.snapshot.playlist.isEmpty)
            const _EmptyState(
              icon: Icons.queue_rounded,
              text: 'Adicione videos do catalogo.',
            )
          else
            ...controller.snapshot.playlist.indexed.map((item) {
              final index = item.$1;
              final entry = item.$2;
              final selected = controller.nowPlaying?.id == entry.id;
              final local = controller.peer.localPathFor(entry.hash) != null;
              final progress = controller.downloads[entry.hash];
              return _PlaylistRow(
                entry: entry,
                selected: selected,
                local: local,
                progress: progress,
                onPlay: () => _run(context, () => controller.playEntry(index)),
              );
            }),
          const SizedBox(height: 18),
          _DownloadStatsPanel(controller: controller),
          const SizedBox(height: 18),
          _PanelTitle(
            key: peersKey,
            icon: Icons.group_rounded,
            title: 'Peers conectados',
          ),
          const SizedBox(height: 10),
          ...controller.snapshot.peers.map(
            (peer) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.computer_rounded,
                color: context.primaryAccent,
              ),
              title: Text(peer.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${peer.host}:${peer.port}',
                style: TextStyle(color: context.textSubtle),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PanelTitle(
            key: eventsKey,
            icon: Icons.terminal_rounded,
            title: 'Eventos',
          ),
          const SizedBox(height: 10),
          ...controller.logs
              .take(14)
              .map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    log,
                    style: TextStyle(color: context.textMuted, fontSize: 12),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title, super.key});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: context.primaryAccent),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _DownloadStatsPanel extends StatelessWidget {
  const _DownloadStatsPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final downloads = controller.downloads.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final active = downloads.where((item) => !item.isComplete).toList();
    final totalReceived = downloads.fold<int>(
      0,
      (total, item) => total + item.receivedBytes,
    );
    final totalBytes = downloads.fold<int>(
      0,
      (total, item) => total + item.totalBytes,
    );
    final totalSpeed = active.fold<double>(
      0,
      (total, item) => total + item.bytesPerSecond,
    );
    final remainingBytes = active.fold<int>(
      0,
      (total, item) => total + (item.totalBytes - item.receivedBytes),
    );
    final eta = totalSpeed > 1
        ? Duration(seconds: (remainingBytes / totalSpeed).ceil())
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PanelTitle(
          icon: Icons.monitor_heart_rounded,
          title: 'Downloads',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricTile(label: 'Ativos', value: '${active.length}'),
            _MetricTile(label: 'Velocidade', value: formatRate(totalSpeed)),
            _MetricTile(
              label: 'Baixado',
              value:
                  '${formatBytes(totalReceived)} / ${formatBytes(totalBytes)}',
            ),
            _MetricTile(
              label: 'Termino',
              value: eta == null ? '--' : formatShortDuration(eta),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (downloads.isEmpty)
          const _EmptyState(
            icon: Icons.speed_rounded,
            text: 'Sem downloads registrados.',
          )
        else
          ...downloads.map((progress) => _DownloadCard(progress: progress)),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: context.raisedBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: context.textSubtle, fontSize: 11),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.progress});

  final DownloadProgress progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.progress * 100).clamp(0, 100);
    final eta = progress.estimatedRemaining;
    final status = progress.isComplete
        ? 'concluido'
        : eta == null
        ? 'calculando'
        : 'termina em ${formatShortDuration(eta)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.rowBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_download_rounded,
                color: context.secondaryAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: TextStyle(color: context.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.progress,
            minHeight: 5,
            color: progress.isComplete
                ? context.primaryAccent
                : context.warningAccent,
            backgroundColor: context.borderStrongColor,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 54,
            child: CustomPaint(
              painter: _SpeedChartPainter(
                samples: progress.speedSamples,
                lineColor: context.secondaryAccent,
                fillColor: context.secondaryAccent.withValues(alpha: 0.16),
                gridColor: context.borderColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _InlineStat(
                icon: Icons.speed_rounded,
                text: formatRate(progress.bytesPerSecond),
              ),
              _InlineStat(icon: Icons.schedule_rounded, text: status),
              _InlineStat(
                icon: Icons.storage_rounded,
                text:
                    '${formatBytes(progress.receivedBytes)} / ${formatBytes(progress.totalBytes)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  const _InlineStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: context.textSubtle),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: context.textMuted, fontSize: 12)),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.entry,
    required this.selected,
    required this.local,
    required this.progress,
    required this.onPlay,
  });

  final PlaylistEntry entry;
  final bool selected;
  final bool local;
  final DownloadProgress? progress;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final downloadProgress = progress?.progress;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? context.selectedRowBackground : context.rowBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? context.primaryAccent : context.borderColor,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Reproduzir',
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      local
                          ? 'Pronto localmente'
                          : _downloadStatus(progress) ?? 'Disponivel na rede',
                      style: TextStyle(color: context.textSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(
                local ? Icons.offline_pin_rounded : Icons.public_rounded,
                color: local ? context.primaryAccent : context.warningAccent,
              ),
            ],
          ),
          if (downloadProgress != null && downloadProgress < 1) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: downloadProgress,
              minHeight: 4,
              color: context.warningAccent,
              backgroundColor: context.borderStrongColor,
            ),
          ],
        ],
      ),
    );
  }

  String? _downloadStatus(DownloadProgress? progress) {
    if (progress == null) {
      return null;
    }
    if (progress.isComplete) {
      return 'Download concluido';
    }
    final eta = progress.estimatedRemaining;
    final etaText = eta == null ? 'ETA calculando' : formatShortDuration(eta);
    return '${progress.status} - ${formatRate(progress.bytesPerSecond)} - $etaText';
  }
}

class _SpeedChartPainter extends CustomPainter {
  const _SpeedChartPainter({
    required this.samples,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<DownloadSpeedSample> samples;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.length < 2) {
      final idlePaint = Paint()
        ..color = gridColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height - 1),
        Offset(size.width, size.height - 1),
        idlePaint,
      );
      return;
    }

    var maxSpeed = 1.0;
    for (final sample in samples) {
      if (sample.bytesPerSecond > maxSpeed) {
        maxSpeed = sample.bytesPerSecond;
      }
    }

    final line = Path();
    final fill = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = samples.length == 1
          ? 0.0
          : size.width * i / (samples.length - 1);
      final normalized = (samples[i].bytesPerSecond / maxSpeed)
          .clamp(0, 1)
          .toDouble();
      final y = size.height - (normalized * (size.height - 4)) - 2;
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedChartPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.raisedBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: context.textMuted)),
          ),
        ],
      ),
    );
  }
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}
