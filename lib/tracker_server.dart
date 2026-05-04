import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'models.dart';

typedef LogWriter = void Function(String message);

class TrackerServer {
  TrackerServer({
    required this.onLog,
    required this.onChanged,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatTimeout = const Duration(seconds: 5),
    this.replicaCount = 2,
  });

  final LogWriter onLog;
  final VoidCallback onChanged;
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final int replicaCount;

  ServerSocket? _server;
  Timer? _heartbeatTimer;
  bool _heartbeatRunning = false;
  bool _repairRunning = false;
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
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_checkPeerHeartbeats());
    });
  }

  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
      final request = _decodeRequestLine(line);
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
      case 'UNREGISTER':
        return _unregister(request);
      case 'LIST':
        return {'ok': true, 'snapshot': snapshotJson()};
      case 'WHEREIS':
      case 'LOOKUP':
      case 'DOWNLOAD':
        return _lookup(request);
      case 'SEARCH':
        return _search(request);
      case 'ADD_PLAYLIST':
        return _addPlaylist(request);
      default:
        return {'ok': false, 'error': 'Comando desconhecido'};
    }
  }

  Map<String, Object?> _decodeRequestLine(String line) {
    final trimmed = line.trim();
    if (trimmed.startsWith('{')) {
      return (jsonDecode(trimmed) as Map).cast<String, Object?>();
    }
    final firstSpace = trimmed.indexOf(' ');
    final command =
        (firstSpace == -1 ? trimmed : trimmed.substring(0, firstSpace))
            .toUpperCase();
    final argument = firstSpace == -1 ? '' : trimmed.substring(firstSpace + 1);
    return switch (command) {
      'WHEREIS' => {'type': 'WHEREIS', 'name': argument},
      'SEARCH' => {'type': 'SEARCH', 'query': argument},
      'LIST' => {'type': 'LIST'},
      _ => {'type': command, 'name': argument},
    };
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

  Map<String, Object?> _unregister(Map<String, Object?> request) {
    final peerId = request['peerId'] as String? ?? '';
    if (peerId.isEmpty) {
      return {'ok': false, 'error': 'peerId obrigatorio'};
    }
    final removed = _peers[peerId];
    if (removed == null) {
      return {'ok': true, 'removed': false, 'snapshot': snapshotJson()};
    }
    _removePeer(peerId);
    onLog('${removed.name} desregistrou do tracker');
    onChanged();
    unawaited(_repairUnderReplicatedVideos());
    return {'ok': true, 'removed': true, 'snapshot': snapshotJson()};
  }

  Map<String, Object?> _lookup(Map<String, Object?> request) {
    final hash = request['hash'] as String? ?? '';
    if (hash.isNotEmpty) {
      return _lookupHash(hash);
    }

    final name = request['name'] as String? ?? '';
    if (name.isNotEmpty) {
      return _lookupName(name);
    }

    return {
      'ok': false,
      'error': 'Informe hash ou name para consultar o recurso',
    };
  }

  Map<String, Object?> _lookupHash(String hash) {
    final owners = _ownersByHash[hash] ?? const <String>{};
    final peers = owners.map((id) => _peers[id]).whereType<PeerInfo>().toList();
    return {
      'ok': true,
      'video': _videos[hash]?.toJson(),
      'peers': peers.map((peer) => peer.toJson()).toList(),
    };
  }

  Map<String, Object?> _lookupName(String name) {
    final query = name.trim().toLowerCase();
    VideoItem? match;
    for (final video in _videos.values) {
      if (video.name.toLowerCase() == query) {
        match = video;
        break;
      }
    }
    if (match == null) {
      return {'ok': false, 'error': 'Recurso "$name" nao encontrado'};
    }
    return _lookupHash(match.hash);
  }

  Map<String, Object?> _search(Map<String, Object?> request) {
    final query =
        (request['query'] as String? ?? request['name'] as String? ?? '')
            .trim()
            .toLowerCase();
    if (query.isEmpty) {
      return {'ok': false, 'error': 'Informe uma palavra para buscar'};
    }
    final results = <Map<String, Object?>>[];
    for (final video in _videos.values) {
      if (!video.name.toLowerCase().contains(query)) {
        continue;
      }
      final owners = _ownersByHash[video.hash] ?? const <String>{};
      final peers = owners.map((id) => _peers[id]).whereType<PeerInfo>();
      results.add({
        'video': video.toJson(),
        'peers': peers.map((peer) => peer.toJson()).toList(),
      });
    }
    return {'ok': true, 'results': results};
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

  Future<void> _checkPeerHeartbeats() async {
    if (_heartbeatRunning || _peers.isEmpty) {
      return;
    }
    _heartbeatRunning = true;
    var changed = false;
    try {
      final peers = List<PeerInfo>.from(_peers.values);
      for (final peer in peers) {
        if (_peers[peer.id] == null) {
          continue;
        }
        final alive = await _sendHeartbeat(peer);
        if (alive) {
          final current = _peers[peer.id];
          if (current != null) {
            _peers[peer.id] = PeerInfo(
              id: current.id,
              name: current.name,
              host: current.host,
              port: current.port,
              lastSeen: DateTime.now(),
            );
          }
          continue;
        }
        _removePeer(peer.id);
        changed = true;
        onLog('${peer.name} removido: heartbeat sem resposta');
      }
    } finally {
      _heartbeatRunning = false;
    }
    if (changed) {
      onChanged();
      unawaited(_repairUnderReplicatedVideos());
    }
  }

  Future<bool> _sendHeartbeat(PeerInfo peer) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        peer.host,
        peer.port,
        timeout: heartbeatTimeout,
      );
      socket.write(encodeMessage({'type': 'HEARTBEAT', 'peerId': peer.id}));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(heartbeatTimeout);
      final response = jsonDecode(line) as Map<String, Object?>;
      return response['ok'] == true &&
          response['type'] == 'HEARTBEAT_ACK' &&
          response['peerId'] == peer.id;
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  void _removePeer(String peerId) {
    _peers.remove(peerId);
    final hashesWithoutOwners = <String>[];
    for (final entry in _ownersByHash.entries) {
      entry.value.remove(peerId);
      if (entry.value.isEmpty) {
        hashesWithoutOwners.add(entry.key);
      }
    }
    for (final hash in hashesWithoutOwners) {
      _ownersByHash.remove(hash);
      _videos.remove(hash);
    }
  }

  Future<void> _repairUnderReplicatedVideos() async {
    if (_repairRunning || _peers.isEmpty) {
      return;
    }
    _repairRunning = true;
    try {
      final desiredOwners = replicaCount + 1;
      final videos = List<VideoItem>.from(_videos.values);
      for (final video in videos) {
        final ownerIds = Set<String>.from(_ownersByHash[video.hash] ?? {});
        ownerIds.removeWhere((id) => !_peers.containsKey(id));
        if (ownerIds.isEmpty) {
          _ownersByHash.remove(video.hash);
          _videos.remove(video.hash);
          continue;
        }
        final desiredForNetwork = min(desiredOwners, _peers.length);
        final missing = desiredForNetwork - ownerIds.length;
        if (missing <= 0) {
          continue;
        }
        final targets = _peers.values
            .where((peer) => !ownerIds.contains(peer.id))
            .take(missing)
            .toList();
        if (targets.isEmpty) {
          continue;
        }
        final owners = ownerIds.map((id) => _peers[id]).whereType<PeerInfo>();
        for (final owner in owners) {
          final accepted = await _requestReplication(
            owner: owner,
            video: video,
            targets: targets,
          );
          if (accepted) {
            break;
          }
        }
      }
    } finally {
      _repairRunning = false;
    }
  }

  Future<bool> _requestReplication({
    required PeerInfo owner,
    required VideoItem video,
    required List<PeerInfo> targets,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        owner.host,
        owner.port,
        timeout: const Duration(seconds: 8),
      );
      socket.write(
        encodeMessage({
          'type': 'REPLICATE_RESOURCE',
          'video': video.toJson(),
          'targets': targets.map((peer) => peer.toJson()).toList(),
        }),
      );
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(hours: 4));
      final response = jsonDecode(line) as Map<String, Object?>;
      final ok = response['ok'] == true;
      if (ok) {
        onLog(
          'Re-replicacao solicitada para "${video.name}" via ${owner.name}',
        );
      }
      return ok;
    } on Object catch (error) {
      onLog('Re-replicacao falhou via ${owner.name}: $error');
      return false;
    } finally {
      socket?.destroy();
    }
  }
}

typedef VoidCallback = void Function();
