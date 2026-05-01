import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
      if (request['type'] == 'RELAY_DOWNLOAD') {
        await _relayDownload(request, socket);
        return;
      }
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

  Future<void> _relayDownload(
    Map<String, Object?> request,
    Socket client,
  ) async {
    final hash = request['hash'] as String? ?? '';
    final video = _videos[hash];
    if (video == null) {
      client.write(
        encodeMessage({'ok': false, 'error': 'Video nao registrado'}),
      );
      return;
    }

    final offset = (request['offset'] as num?)?.toInt() ?? 0;
    if (offset < 0 || offset > video.size) {
      client.write(encodeMessage({'ok': false, 'error': 'Offset invalido'}));
      return;
    }

    final available = video.size - offset;
    final length = min(
      (request['length'] as num?)?.toInt() ?? available,
      available,
    );
    final encrypted = request['encrypted'] == true;
    final requesterId = request['requesterId'] as String? ?? '';
    final owners = (_ownersByHash[hash] ?? const <String>{})
        .map((id) => _peers[id])
        .whereType<PeerInfo>()
        .where((peer) => peer.id != requesterId)
        .toList();

    for (final owner in owners) {
      try {
        await _pipePeerThroughRelay(
          owner: owner,
          video: video,
          offset: offset,
          length: length,
          encrypted: encrypted,
          client: client,
        );
        onLog('Relay enviou "${video.name}" via ${owner.name}');
        return;
      } on Object catch (error) {
        onLog('Relay falhou via ${owner.name}: $error');
      }
    }

    client.write(
      encodeMessage({
        'ok': false,
        'error': 'Nenhum owner alcancavel via relay',
      }),
    );
  }

  Future<void> _pipePeerThroughRelay({
    required PeerInfo owner,
    required VideoItem video,
    required int offset,
    required int length,
    required bool encrypted,
    required Socket client,
  }) async {
    final peerSocket = await Socket.connect(
      owner.host,
      owner.port,
      timeout: const Duration(seconds: 8),
    );
    final completer = Completer<void>();
    var headerParsed = false;
    var headerBytes = <int>[];
    var failed = false;

    void completeWithError(Object error) {
      failed = true;
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
      peerSocket.destroy();
    }

    peerSocket.write(
      encodeMessage({
        'type': 'GET_FILE',
        'hash': video.hash,
        'offset': offset,
        'length': length,
        'encrypted': encrypted,
      }),
    );
    await peerSocket.flush();

    peerSocket.listen(
      (data) {
        if (failed) {
          return;
        }
        if (!headerParsed) {
          final newline = data.indexOf(10);
          if (newline == -1) {
            headerBytes.addAll(data);
            return;
          }
          headerBytes.addAll(data.sublist(0, newline));
          final header =
              jsonDecode(utf8.decode(headerBytes)) as Map<String, Object?>;
          if (header['ok'] != true) {
            completeWithError(
              StateError(header['error'] as String? ?? 'Peer recusou relay'),
            );
            return;
          }
          headerParsed = true;
          client.write(
            encodeMessage({
              'ok': true,
              'name': video.name,
              'size': video.size,
              'offset': offset,
              'length': length,
              'encrypted': header['encrypted'] == true,
              'relay': true,
              'peerName': owner.name,
              if (header['encrypted'] == true) 'cipher': transferCipherName,
            }),
          );
          final body = data.sublist(newline + 1);
          if (body.isNotEmpty) {
            client.add(body);
          }
          return;
        }
        client.add(data);
      },
      onError: completeWithError,
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    await completer.future.timeout(const Duration(hours: 4));
    await peerSocket.close();
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
