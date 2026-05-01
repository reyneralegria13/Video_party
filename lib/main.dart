import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';

void main() {
  runApp(const VideoPartyApp());
}

class VideoPartyApp extends StatelessWidget {
  const VideoPartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Party P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff00c2a8),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101114),
        useMaterial3: true,
      ),
      home: const PartyHomePage(),
    );
  }
}

class PartyHomePage extends StatefulWidget {
  const PartyHomePage({super.key});

  @override
  State<PartyHomePage> createState() => _PartyHomePageState();
}

class _PartyHomePageState extends State<PartyHomePage> {
  late final AppController controller;
  late final TextEditingController peerName;
  late final TextEditingController trackerHost;
  late final TextEditingController trackerPort;
  late final TextEditingController advertisedHost;
  late final TextEditingController uploadPort;
  late final TextEditingController folderPath;

  @override
  void initState() {
    super.initState();
    controller = AppController();
    peerName = TextEditingController(text: controller.peerName);
    trackerHost = TextEditingController(text: controller.trackerHost);
    trackerPort = TextEditingController(text: '${controller.trackerPort}');
    advertisedHost = TextEditingController(text: controller.advertisedHost);
    uploadPort = TextEditingController(text: '${controller.uploadPort}');
    folderPath = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
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
                          const _SideBar(),
                          Expanded(
                            child: _MainArea(
                              controller: controller,
                              peerName: peerName,
                              trackerHost: trackerHost,
                              trackerPort: trackerPort,
                              advertisedHost: advertisedHost,
                              uploadPort: uploadPort,
                              folderPath: folderPath,
                            ),
                          ),
                          SizedBox(
                            width: 360,
                            child: _RightPanel(controller: controller),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _Header(controller: controller),
                          const SizedBox(height: 16),
                          _ControlPanel(
                            controller: controller,
                            peerName: peerName,
                            trackerHost: trackerHost,
                            trackerPort: trackerPort,
                            advertisedHost: advertisedHost,
                            uploadPort: uploadPort,
                            folderPath: folderPath,
                          ),
                          const SizedBox(height: 16),
                          _NowPlaying(controller: controller),
                          const SizedBox(height: 16),
                          _Library(controller: controller),
                          const SizedBox(height: 16),
                          _RightPanel(controller: controller),
                        ],
                      );
                return wide
                    ? content
                    : ColoredBox(
                        color: const Color(0xff101114),
                        child: content,
                      );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      color: const Color(0xff181a1f),
      child: const Column(
        children: [
          SizedBox(height: 20),
          Icon(Icons.movie_filter_rounded, color: Color(0xff00c2a8), size: 34),
          SizedBox(height: 28),
          _NavIcon(icon: Icons.home_rounded, selected: true),
          _NavIcon(icon: Icons.queue_music_rounded),
          _NavIcon(icon: Icons.cloud_download_rounded),
          _NavIcon(icon: Icons.settings_rounded),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icon, this.selected = false});

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IconButton(
        tooltip: '',
        onPressed: () {},
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? const Color(0xff25322f)
              : Colors.transparent,
          fixedSize: const Size(48, 48),
        ),
        icon: Icon(
          icon,
          color: selected ? const Color(0xff00c2a8) : Colors.white70,
        ),
      ),
    );
  }
}

class _MainArea extends StatelessWidget {
  const _MainArea({
    required this.controller,
    required this.peerName,
    required this.trackerHost,
    required this.trackerPort,
    required this.advertisedHost,
    required this.uploadPort,
    required this.folderPath,
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
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _Header(controller: controller),
        const SizedBox(height: 16),
        _ControlPanel(
          controller: controller,
          peerName: peerName,
          trackerHost: trackerHost,
          trackerPort: trackerPort,
          advertisedHost: advertisedHost,
          uploadPort: uploadPort,
          folderPath: folderPath,
        ),
        const SizedBox(height: 18),
        _NowPlaying(controller: controller),
        const SizedBox(height: 18),
        _Library(controller: controller),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Video Party P2P',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Playlist colaborativa com tracker hibrido, peers TCP e prefetch.',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
        _StatusChip(
          icon: Icons.hub_rounded,
          label: controller.trackerRunning ? 'Tracker ativo' : 'Tracker remoto',
          active: controller.trackerRunning,
        ),
        const SizedBox(width: 10),
        _StatusChip(
          icon: Icons.upload_rounded,
          label: controller.peerServing ? 'Upload ativo' : 'Upload parado',
          active: controller.peerServing,
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
        color: active ? const Color(0xff183a32) : const Color(0xff25272d),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? const Color(0xff38e8c6) : Colors.white54,
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
        color: const Color(0xff181a1f),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
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
          fillColor: const Color(0xff101114),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entry = controller.nowPlaying;
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
        color: const Color(0xff1b1d22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 6.7,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xff090a0c),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PlayerBackdropPainter()),
                  ),
                  Center(
                    child: Icon(
                      controller.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 76,
                      color: const Color(0xff00c2a8),
                    ),
                  ),
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
                          color: const Color(0xff00c2a8),
                          backgroundColor: Colors.white12,
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
                style: const TextStyle(color: Colors.white70),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  'Downloads: ${controller.downloadFolder}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xff15181c);
    for (var i = 0; i < 10; i++) {
      final x = size.width * i / 9;
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), paint);
    }
    final accent = Paint()..color = const Color(0x2238e8c6);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Library extends StatelessWidget {
  const _Library({required this.controller});

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
        color: const Color(0xff181a1f),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: local ? const Color(0xff00c2a8) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xff24272e),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Icon(
                  local
                      ? Icons.offline_pin_rounded
                      : Icons.movie_creation_rounded,
                  color: local
                      ? const Color(0xff00c2a8)
                      : const Color(0xffffbd59),
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
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  local
                      ? 'local'
                      : '${video.hash.substring(0, video.hash.length < 8 ? video.hash.length : 8)}...',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
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
  const _RightPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xff15171b),
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _PanelTitle(
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
          _PanelTitle(icon: Icons.group_rounded, title: 'Peers conectados'),
          const SizedBox(height: 10),
          ...controller.snapshot.peers.map(
            (peer) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.computer_rounded,
                color: Color(0xff00c2a8),
              ),
              title: Text(peer.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${peer.host}:${peer.port}',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _PanelTitle(icon: Icons.terminal_rounded, title: 'Eventos'),
          const SizedBox(height: 10),
          ...controller.logs
              .take(14)
              .map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    log,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xff00c2a8)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
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
        color: selected ? const Color(0xff20342f) : const Color(0xff1c1f24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xff00c2a8) : Colors.white10,
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
                          : progress?.status ?? 'Disponivel na rede',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                local ? Icons.offline_pin_rounded : Icons.public_rounded,
                color: local
                    ? const Color(0xff00c2a8)
                    : const Color(0xffffbd59),
              ),
            ],
          ),
          if (downloadProgress != null && downloadProgress < 1) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: downloadProgress,
              minHeight: 4,
              color: const Color(0xffffbd59),
              backgroundColor: Colors.white12,
            ),
          ],
        ],
      ),
    );
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
        color: const Color(0xff1b1d22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white60)),
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
