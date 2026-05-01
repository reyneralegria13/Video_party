import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

typedef LogWriter = void Function(String message);

class TrackerServer {
  TrackerServer({required this.onLog, required this.onChanged});

  final LogWriter onLog;
  final VoidCallback onChanged;

  ServerSocket? _server;
  final Map<String, VideoItem> _videos = {};
  final Map<String, PeerInfo> _peers = {};
  final Map<String, Set<String>> _ownersByHash = {};
  final List<PlaylistEntry> _playlist = [];

  bool get isRunning => _server != null;

  Future<void> start({required String host, required int port}) async {
    if (_server != null) {
      return;
    }
    _server = await ServerSocket.bind(host, port, shared: true);
    onLog('Tracker ouvindo em $host:$port');
    _server!.listen(
      _handleClient,
      onError: (Object error) => onLog('Erro no tracker: $error'),
      onDone: () => onLog('Tracker finalizado'),
    );
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    onLog('Tracker parado');
  }

  TrackerSnapshot snapshot() => TrackerSnapshot(
    videos: _videos.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    peers: _peers.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    playlist: List.unmodifiable(_playlist),
  );

  Future<void> _handleClient(Socket socket) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      final request = jsonDecode(line) as Map<String, Object?>;
      final response = _dispatch(request);
      socket.write(encodeMessage(response));
    } on Object catch (error) {
      socket.write(encodeMessage({'ok': false, 'error': '$error'}));
    } finally {
      await socket.flush();
      await socket.close();
    }
  }

  Map<String, Object?> _dispatch(Map<String, Object?> request) {
    switch (request['type']) {
      case 'REGISTER':
        return _register(request);
      case 'LIST':
        return {'ok': true, 'snapshot': snapshotJson()};
      case 'LOOKUP':
      case 'DOWNLOAD':
        return _lookup(request['hash'] as String? ?? '');
      case 'ADD_PLAYLIST':
        return _addPlaylist(request);
      default:
        return {'ok': false, 'error': 'Comando desconhecido'};
    }
  }

  Map<String, Object?> _register(Map<String, Object?> request) {
    final peerJson = (request['peer'] as Map).cast<String, Object?>();
    final peer = PeerInfo.fromJson({
      ...peerJson,
      'lastSeen': DateTime.now().toIso8601String(),
    });
    _peers[peer.id] = peer;

    for (final owners in _ownersByHash.values) {
      owners.remove(peer.id);
    }

    final videos = (request['videos'] as List? ?? []).whereType<Map>().map(
      (item) => VideoItem.fromJson(item.cast<String, Object?>()),
    );
    var count = 0;
    for (final video in videos) {
      if (video.hash.isEmpty) {
        continue;
      }
      _videos[video.hash] = VideoItem(
        name: video.name,
        hash: video.hash,
        size: video.size,
      );
      _ownersByHash.putIfAbsent(video.hash, () => <String>{}).add(peer.id);
      count++;
    }

    onLog('${peer.name} registrou $count video(s)');
    onChanged();
    return {'ok': true, 'snapshot': snapshotJson()};
  }

  Map<String, Object?> _lookup(String hash) {
    final owners = _ownersByHash[hash] ?? const <String>{};
    final peers = owners.map((id) => _peers[id]).whereType<PeerInfo>().toList();
    return {
      'ok': true,
      'video': _videos[hash]?.toJson(),
      'peers': peers.map((peer) => peer.toJson()).toList(),
    };
  }

  Map<String, Object?> _addPlaylist(Map<String, Object?> request) {
    final hash = request['hash'] as String? ?? '';
    final video = _videos[hash];
    if (video == null) {
      return {'ok': false, 'error': 'Video nao registrado no tracker'};
    }
    final entry = PlaylistEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      hash: hash,
      title: request['title'] as String? ?? video.name,
      addedBy: request['peerName'] as String? ?? 'peer',
      addedAt: DateTime.now(),
    );
    _playlist.add(entry);
    onLog('${entry.addedBy} adicionou "${entry.title}" na playlist');
    onChanged();
    return {'ok': true, 'entry': entry.toJson(), 'snapshot': snapshotJson()};
  }

  Map<String, Object?> snapshotJson() {
    final data = snapshot();
    return {
      'videos': data.videos.map((item) => item.toJson()).toList(),
      'peers': data.peers.map((item) => item.toJson()).toList(),
      'playlist': data.playlist.map((item) => item.toJson()).toList(),
    };
  }
}

typedef VoidCallback = void Function();
