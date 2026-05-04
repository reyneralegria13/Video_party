import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'models.dart';
import 'peer_node.dart';
import 'tracker_server.dart';

enum AppVisualTheme { standard, light, system }

class AppController extends ChangeNotifier {
  AppController() : peer = PeerNode(onLog: _pendingLog) {
    _pendingController = this;
    _downloadDirectory = Directory(_defaultDownloadPath());
    _configurePeer();
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
  final Map<String, _DownloadTelemetry> _downloadTelemetry = {};
  final Map<String, DateTime> _lastDownloadNotification = {};
  final Set<String> _prefetching = {};
  bool _registered = false;

  String peerName = 'DJ Video';
  String trackerHost = '127.0.0.1';
  int trackerPort = 4040;
  String advertisedHost = '127.0.0.1';
  int uploadPort = 5051;
  String folderPath = '';
  AppVisualTheme visualTheme = AppVisualTheme.standard;

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
    _configurePeer();
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
    _configurePeer();
    snapshot = await peer.register(
      trackerHost: trackerHost.trim(),
      trackerPort: trackerPort,
      peerName: peerName.trim().isEmpty ? 'Peer sem nome' : peerName.trim(),
      advertisedHost: advertisedHost.trim(),
      advertisedPort: uploadPort,
    );
    _registered = true;
    _log('Registro atualizado no tracker.');
    final replicas = await peer.ensureReplication(
      trackerHost: trackerHost.trim(),
      trackerPort: trackerPort,
    );
    if (replicas > 0) {
      _log('$replicas replica(s) voluntaria(s) criada(s).');
      await refresh();
    }
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
    _updateDownloadProgress(
      DownloadProgress(
        hash: entry.hash,
        title: entry.title,
        receivedBytes: 0,
        totalBytes: video.size,
        status: reason,
      ),
      force: true,
    );
    try {
      await peer.downloadFromPeers(
        peers: peers,
        video: video,
        outputDirectory: _downloadDirectory,
        maxParallelDownloads: reason == 'prefetch' ? 1 : null,
        onProgress: (progress) {
          _updateDownloadProgress(progress);
        },
      );
    } on Object catch (error) {
      _log('Download direto falhou: $error');
      try {
        await _retryDirectDownload(video);
      } on Object catch (retryError) {
        _log('Retry direto falhou: $retryError');
        await peer.downloadViaTrackerRelay(
          trackerHost: trackerHost.trim(),
          trackerPort: trackerPort,
          video: video,
          outputDirectory: _downloadDirectory,
          onProgress: (progress) {
            _updateDownloadProgress(progress);
          },
        );
      }
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
    _configurePeer();
  }

  void updateVisualTheme(AppVisualTheme value) {
    visualTheme = value;
    notifyListeners();
  }

  void _syncLocalSnapshot() {
    if (tracker != null) {
      snapshot = tracker!.snapshot();
      notifyListeners();
    }
  }

  Future<void> _retryDirectDownload(VideoItem video) async {
    final tried = <String>{};
    while (true) {
      final response = await requestTracker(trackerHost.trim(), trackerPort, {
        'type': 'DOWNLOAD',
        'hash': video.hash,
      });
      if (response['ok'] != true) {
        throw StateError(response['error'] as String? ?? 'Lookup falhou');
      }
      final candidates = (response['peers'] as List? ?? [])
          .whereType<Map>()
          .map((item) => PeerInfo.fromJson(item.cast<String, Object?>()))
          .where((candidate) => candidate.id != peer.id)
          .where((candidate) => !tried.contains(candidate.id))
          .toList();
      if (candidates.isEmpty) {
        throw StateError('Nenhum peer alternativo respondeu ao tracker.');
      }
      for (final candidate in candidates) {
        tried.add(candidate.id);
        try {
          _log('Tentando outro peer: ${candidate.name}');
          await peer.downloadFromPeers(
            peers: [candidate],
            video: video,
            outputDirectory: _downloadDirectory,
            onProgress: (progress) {
              _updateDownloadProgress(progress);
            },
          );
          return;
        } on Object catch (error) {
          _log('${candidate.name} tambem falhou: $error');
        }
      }
    }
  }

  void _configurePeer() {
    peer.configure(
      storageDirectory: _downloadDirectory,
      trackerHost: trackerHost.trim(),
      trackerPort: trackerPort,
      peerName: peerName.trim().isEmpty ? 'Peer sem nome' : peerName.trim(),
      advertisedHost: advertisedHost.trim(),
      advertisedPort: uploadPort,
    );
  }

  void _updateDownloadProgress(
    DownloadProgress progress, {
    bool force = false,
  }) {
    final now = DateTime.now();
    final telemetry = _downloadTelemetry.putIfAbsent(
      progress.hash,
      () => _DownloadTelemetry(now, progress.receivedBytes),
    );
    downloads[progress.hash] = telemetry.apply(progress, now);

    final lastNotification = _lastDownloadNotification[progress.hash];
    final shouldNotify =
        force ||
        progress.isComplete ||
        lastNotification == null ||
        now.difference(lastNotification) >= const Duration(milliseconds: 250);
    if (!shouldNotify) {
      return;
    }
    _lastDownloadNotification[progress.hash] = now;
    notifyListeners();
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
      final seconds = position.inSeconds;
      if (seconds == playbackSeconds) {
        return;
      }
      playbackSeconds = seconds;
      notifyListeners();
    });
    _durationSubscription = player.stream.duration.listen((duration) {
      final seconds = duration.inSeconds == 0 ? 1 : duration.inSeconds;
      if (seconds == playbackDuration) {
        return;
      }
      playbackDuration = seconds;
      notifyListeners();
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      if (playing == isPlaying) {
        return;
      }
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

  Future<void> _unregisterQuietly() async {
    if (!_registered) {
      return;
    }
    try {
      await peer.unregister(
        trackerHost: trackerHost.trim(),
        trackerPort: trackerPort,
      );
      _registered = false;
    } on Object {
      // O app pode fechar sem tracker ativo; o heartbeat cobre esse caso.
    }
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_playingSubscription?.cancel());
    unawaited(_completedSubscription?.cancel());
    unawaited(_player?.dispose());
    unawaited(_unregisterQuietly());
    unawaited(peer.stopUploadServer());
    unawaited(tracker?.stop());
    super.dispose();
  }
}

class _DownloadTelemetry {
  _DownloadTelemetry(this.lastAt, this.lastBytes) : lastSampleAt = lastAt;

  static const _maxSamples = 28;

  DateTime lastAt;
  DateTime lastSampleAt;
  int lastBytes;
  double lastSpeed = 0;
  final List<DownloadSpeedSample> samples = [];

  DownloadProgress apply(DownloadProgress progress, DateTime now) {
    if (progress.receivedBytes < lastBytes) {
      samples.clear();
      lastSpeed = 0;
      lastBytes = progress.receivedBytes;
      lastAt = now;
      lastSampleAt = now;
    }

    final elapsed = now.difference(lastAt);
    var speed = lastSpeed;
    if (elapsed.inMilliseconds > 0 && progress.receivedBytes >= lastBytes) {
      final byteDelta = progress.receivedBytes - lastBytes;
      final instantSpeed = byteDelta * 1000 / elapsed.inMilliseconds;
      speed = lastSpeed == 0
          ? instantSpeed
          : (lastSpeed * 0.65) + (instantSpeed * 0.35);
    }

    final shouldSample =
        samples.isEmpty ||
        now.difference(lastSampleAt) >= const Duration(milliseconds: 500) ||
        progress.isComplete;
    if (shouldSample) {
      samples.add(DownloadSpeedSample(at: now, bytesPerSecond: speed));
      if (samples.length > _maxSamples) {
        samples.removeRange(0, samples.length - _maxSamples);
      }
      lastSampleAt = now;
    }

    lastAt = now;
    lastBytes = progress.receivedBytes;
    lastSpeed = speed;

    Duration? eta;
    if (progress.isComplete) {
      eta = Duration.zero;
    } else if (speed > 1 && progress.totalBytes > progress.receivedBytes) {
      final remainingBytes = progress.totalBytes - progress.receivedBytes;
      eta = Duration(seconds: (remainingBytes / speed).ceil());
    }

    return progress.copyWith(
      bytesPerSecond: speed,
      estimatedRemaining: eta,
      speedSamples: List.unmodifiable(samples),
    );
  }
}
