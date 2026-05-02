import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';
import 'peer_node.dart';
import 'tracker_server.dart';

class AppController extends ChangeNotifier {
  AppController() : peer = PeerNode(onLog: _pendingLog) {
    _pendingController = this;
    _downloadDirectory = Directory(_defaultDownloadPath());
  }

  static AppController? _pendingController;

  static void _pendingLog(String message) {
    _pendingController?._log(message);
  }

  final PeerNode peer;
  Player? _player;
  VideoController? videoController;
  late final Directory _downloadDirectory;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;

  TrackerServer? tracker;
  TrackerSnapshot snapshot = TrackerSnapshot.empty();
  final List<String> logs = [];
  final Map<String, DownloadProgress> downloads = {};
  final Set<String> _prefetching = {};

  String peerName = 'DJ Video';
  String trackerHost = '127.0.0.1';
  int trackerPort = 4040;
  String advertisedHost = '127.0.0.1';
  int uploadPort = 5051;
  String folderPath = '';

  PlaylistEntry? nowPlaying;
  int nowPlayingIndex = -1;
  bool isPlaying = false;
  int playbackSeconds = 0;
  int playbackDuration = 1;

  bool get trackerRunning => tracker?.isRunning ?? false;
  bool get peerServing => peer.isServing;
  List<VideoItem> get library => peer.library;
  String get downloadFolder => _downloadDirectory.path;

  Future<void> startTracker() async {
    tracker ??= TrackerServer(onLog: _log, onChanged: _syncLocalSnapshot);
    await tracker!.start(host: '0.0.0.0', port: trackerPort);
    trackerHost = '127.0.0.1';
    _syncLocalSnapshot();
    notifyListeners();
  }

  Future<void> startPeerServer() async {
    await peer.startUploadServer(host: '0.0.0.0', port: uploadPort);
    notifyListeners();
  }

  Future<void> scanAndRegister() async {
    if (folderPath.trim().isEmpty) {
      throw StateError('Informe a pasta com os videos.');
    }
    _log('Escaneando pasta local...');
    await peer.scanFolder(folderPath.trim());
    await register();
  }

  Future<void> register() async {
    snapshot = await peer.register(
      trackerHost: trackerHost.trim(),
      trackerPort: trackerPort,
      peerName: peerName.trim().isEmpty ? 'Peer sem nome' : peerName.trim(),
      advertisedHost: advertisedHost.trim(),
      advertisedPort: uploadPort,
    );
    _log('Registro atualizado no tracker.');
    notifyListeners();
  }

  Future<void> refresh() async {
    final response = await requestTracker(trackerHost.trim(), trackerPort, {
      'type': 'LIST',
    });
    if (response['ok'] != true) {
      throw StateError(response['error'] as String? ?? 'Falha ao listar');
    }
    snapshot = TrackerSnapshot.fromJson(
      (response['snapshot'] as Map).cast<String, Object?>(),
    );
    notifyListeners();
  }

  Future<void> addToPlaylist(VideoItem video) async {
    final response = await requestTracker(trackerHost.trim(), trackerPort, {
      'type': 'ADD_PLAYLIST',
      'hash': video.hash,
      'title': video.name,
      'peerName': peerName,
    });
    if (response['ok'] != true) {
      throw StateError(response['error'] as String? ?? 'Falha ao adicionar');
    }
    snapshot = TrackerSnapshot.fromJson(
      (response['snapshot'] as Map).cast<String, Object?>(),
    );
    notifyListeners();
  }

  Future<void> playEntry(int index) async {
    if (index < 0 || index >= snapshot.playlist.length) {
      return;
    }
    final entry = snapshot.playlist[index];
    nowPlayingIndex = index;
    nowPlaying = entry;
    playbackSeconds = 0;
    playbackDuration = _durationFor(entry.hash);
    isPlaying = false;
    notifyListeners();

    if (peer.localPathFor(entry.hash) == null) {
      _log('Video atual nao esta local. Baixando antes de tocar...');
      await ensureDownloaded(entry, reason: 'download');
    }

    final localPath = peer.localPathFor(entry.hash);
    if (localPath == null) {
      throw StateError('Arquivo local indisponivel para reproducao.');
    }

    final player = _ensurePlayer();
    await player.open(Media(Uri.file(localPath).toString()), play: true);
    _log('Reproduzindo: ${entry.title}');
    notifyListeners();
    unawaited(prefetchNext());
  }

  void togglePlayback() {
    if (nowPlaying == null) {
      if (snapshot.playlist.isNotEmpty) {
        unawaited(playEntry(0));
      }
      return;
    }
    if (isPlaying) {
      unawaited(_player?.pause());
    } else {
      unawaited(_player?.play());
    }
  }

  Future<void> prefetchNext() async {
    final nextIndex = nowPlayingIndex + 1;
    if (nextIndex < 0 || nextIndex >= snapshot.playlist.length) {
      return;
    }
    final next = snapshot.playlist[nextIndex];
    if (peer.localPathFor(next.hash) != null ||
        _prefetching.contains(next.hash)) {
      return;
    }
    _prefetching.add(next.hash);
    _log('Prefetch iniciado: ${next.title}');
    try {
      await ensureDownloaded(next, reason: 'prefetch');
      _log('Prefetch pronto: ${next.title}');
    } finally {
      _prefetching.remove(next.hash);
    }
  }

  Future<void> ensureDownloaded(
    PlaylistEntry entry, {
    required String reason,
  }) async {
    if (peer.localPathFor(entry.hash) != null) {
      return;
    }
    final response = await requestTracker(trackerHost.trim(), trackerPort, {
      'type': 'DOWNLOAD',
      'hash': entry.hash,
    });
    if (response['ok'] != true) {
      throw StateError(response['error'] as String? ?? 'Lookup falhou');
    }
    final video = VideoItem.fromJson(
      (response['video'] as Map?)?.cast<String, Object?>() ??
          {'name': entry.title, 'hash': entry.hash, 'size': 0},
    );
    final peers = (response['peers'] as List? ?? [])
        .whereType<Map>()
        .map((item) => PeerInfo.fromJson(item.cast<String, Object?>()))
        .where((candidate) => candidate.id != peer.id)
        .toList();
    if (peers.isEmpty) {
      throw StateError('Nenhum peer remoto possui "${entry.title}".');
    }
    downloads[entry.hash] = DownloadProgress(
      hash: entry.hash,
      title: entry.title,
      receivedBytes: 0,
      totalBytes: video.size,
      status: reason,
    );
    notifyListeners();
    try {
      await peer.downloadFromPeers(
        peers: peers,
        video: video,
        outputDirectory: _downloadDirectory,
        onProgress: (progress) {
          downloads[entry.hash] = progress;
          notifyListeners();
        },
      );
    } on Object catch (error) {
      _log('Download direto falhou: $error');
      await peer.downloadViaTrackerRelay(
        trackerHost: trackerHost.trim(),
        trackerPort: trackerPort,
        video: video,
        outputDirectory: _downloadDirectory,
        onProgress: (progress) {
          downloads[entry.hash] = progress;
          notifyListeners();
        },
      );
    }
    await register();
  }

  void updateConfig({
    String? peerName,
    String? trackerHost,
    int? trackerPort,
    String? advertisedHost,
    int? uploadPort,
    String? folderPath,
  }) {
    this.peerName = peerName ?? this.peerName;
    this.trackerHost = trackerHost ?? this.trackerHost;
    this.trackerPort = trackerPort ?? this.trackerPort;
    this.advertisedHost = advertisedHost ?? this.advertisedHost;
    this.uploadPort = uploadPort ?? this.uploadPort;
    this.folderPath = folderPath ?? this.folderPath;
  }

  void _syncLocalSnapshot() {
    if (tracker != null) {
      snapshot = tracker!.snapshot();
      notifyListeners();
    }
  }

  void _log(String message) {
    final time =
        '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}';
    logs.insert(0, '[$time] $message');
    if (logs.length > 80) {
      logs.removeRange(80, logs.length);
    }
    notifyListeners();
  }

  int _durationFor(String hash) {
    VideoItem? video;
    for (final item in snapshot.videos) {
      if (item.hash == hash) {
        video = item;
        break;
      }
    }
    if (video == null || video.size == 0) {
      return 60;
    }
    return (45 + (video.size / (1024 * 1024)).clamp(0, 180)).round();
  }

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) {
      return existing;
    }

    MediaKit.ensureInitialized();
    final player = Player();
    _player = player;
    videoController = VideoController(player);
    _positionSubscription = player.stream.position.listen((position) {
      playbackSeconds = position.inSeconds;
      notifyListeners();
    });
    _durationSubscription = player.stream.duration.listen((duration) {
      playbackDuration = duration.inSeconds == 0 ? 1 : duration.inSeconds;
      notifyListeners();
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      isPlaying = playing;
      notifyListeners();
    });
    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed) {
        unawaited(playEntry(nowPlayingIndex + 1));
      }
    });
    notifyListeners();
    return player;
  }

  static String _defaultDownloadPath() {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return '$home${Platform.pathSeparator}VideoPartyDownloads';
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_player?.dispose());
    unawaited(peer.stopUploadServer());
    unawaited(tracker?.stop());
    super.dispose();
  }
}
