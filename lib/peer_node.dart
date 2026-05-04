import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'models.dart';

typedef ProgressWriter = void Function(DownloadProgress progress);
typedef LogWriter = void Function(String message);

const _maxParallelDownloads = 4;
const _transferBlockSize = 1024;
const _simplePeerCipherKey = 'video-party-p2p-demo-key';
const defaultReplicaCount = 2;

class PeerNode {
  PeerNode({required this.onLog});

  final LogWriter onLog;
  final String id =
      'peer-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  ServerSocket? _uploadServer;
  List<VideoItem> _library = [];
  Directory? _storageDirectory;
  String? _trackerHost;
  int? _trackerPort;
  String? _peerName;
  String? _advertisedHost;
  int? _advertisedPort;

  List<VideoItem> get library => List.unmodifiable(_library);
  bool get isServing => _uploadServer != null;

  void configure({
    Directory? storageDirectory,
    String? trackerHost,
    int? trackerPort,
    String? peerName,
    String? advertisedHost,
    int? advertisedPort,
  }) {
    _storageDirectory = storageDirectory ?? _storageDirectory;
    _trackerHost = trackerHost ?? _trackerHost;
    _trackerPort = trackerPort ?? _trackerPort;
    _peerName = peerName ?? _peerName;
    _advertisedHost = advertisedHost ?? _advertisedHost;
    _advertisedPort = advertisedPort ?? _advertisedPort;
  }

  Future<void> startUploadServer({
    required String host,
    required int port,
  }) async {
    if (_uploadServer != null) {
      return;
    }
    _uploadServer = await ServerSocket.bind(host, port, shared: true);
    onLog('Peer ouvindo uploads em $host:$port');
    _uploadServer!.listen(
      _handleUploadClient,
      onError: (Object error) => onLog('Erro no servidor peer: $error'),
    );
  }

  Future<void> stopUploadServer() async {
    await _uploadServer?.close();
    _uploadServer = null;
  }

  Future<List<VideoItem>> scanFolder(String folderPath) async {
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      throw FileSystemException('Pasta nao encontrada', folderPath);
    }
    final found = <VideoItem>[];
    await for (final entity in folder.list(recursive: false)) {
      if (!isVideoFile(entity)) {
        continue;
      }
      final file = File(entity.path);
      final stat = await file.stat();
      final digest = await sha256.bind(file.openRead()).first;
      found.add(
        VideoItem(
          name: entity.uri.pathSegments.last,
          hash: digest.toString(),
          size: stat.size,
          localPath: file.path,
        ),
      );
      onLog('Hash calculado: ${entity.uri.pathSegments.last}');
    }
    _mergeLibrary(found);
    return library;
  }

  Future<TrackerSnapshot> register({
    required String trackerHost,
    required int trackerPort,
    required String peerName,
    required String advertisedHost,
    required int advertisedPort,
  }) async {
    configure(
      trackerHost: trackerHost,
      trackerPort: trackerPort,
      peerName: peerName,
      advertisedHost: advertisedHost,
      advertisedPort: advertisedPort,
    );
    final response = await requestTracker(trackerHost, trackerPort, {
      'type': 'REGISTER',
      'peer': {
        'id': id,
        'name': peerName,
        'host': advertisedHost,
        'port': advertisedPort,
      },
      'videos': _library.map((video) => video.toJson()).toList(),
    });
    if (response['ok'] != true) {
      throw StateError(response['error'] as String? ?? 'Falha no registro');
    }
    return TrackerSnapshot.fromJson(
      (response['snapshot'] as Map).cast<String, Object?>(),
    );
  }

  Future<void> unregister({
    required String trackerHost,
    required int trackerPort,
  }) async {
    final response = await requestTracker(trackerHost, trackerPort, {
      'type': 'UNREGISTER',
      'peerId': id,
    });
    if (response['ok'] != true) {
      throw StateError(response['error'] as String? ?? 'Falha ao desregistrar');
    }
  }

  Future<int> ensureReplication({
    required String trackerHost,
    required int trackerPort,
    int replicaCount = defaultReplicaCount,
  }) async {
    var stored = 0;
    for (final video in _library.where((item) => item.isLocal)) {
      final lookup = await requestTracker(trackerHost, trackerPort, {
        'type': 'LOOKUP',
        'hash': video.hash,
      });
      if (lookup['ok'] != true) {
        continue;
      }
      final owners = (lookup['peers'] as List? ?? [])
          .whereType<Map>()
          .map((item) => PeerInfo.fromJson(item.cast<String, Object?>()))
          .toList();
      final ownerIds = owners.map((peer) => peer.id).toSet();
      final desiredOwners = replicaCount + 1;
      final missing = desiredOwners - ownerIds.length;
      if (missing <= 0) {
        continue;
      }

      final list = await requestTracker(trackerHost, trackerPort, {
        'type': 'LIST',
      });
      if (list['ok'] != true) {
        continue;
      }
      final snapshot = TrackerSnapshot.fromJson(
        (list['snapshot'] as Map).cast<String, Object?>(),
      );
      final targets = snapshot.peers
          .where((peer) => peer.id != id && !ownerIds.contains(peer.id))
          .take(missing)
          .toList();
      if (targets.isEmpty) {
        onLog('Sem peers livres para replicar ${video.name}');
        continue;
      }

      stored += await replicateVideoToPeers(video: video, targets: targets);
    }
    return stored;
  }

  Future<int> replicateVideoToPeers({
    required VideoItem video,
    required List<PeerInfo> targets,
  }) async {
    final source = _selfInfo();
    var stored = 0;
    for (final target in targets) {
      if (target.id == id) {
        continue;
      }
      try {
        final socket = await Socket.connect(
          target.host,
          target.port,
          timeout: const Duration(seconds: 8),
        );
        socket.write(
          encodeMessage({
            'type': 'STORE_REPLICA',
            'video': video.toJson(),
            'source': source.toJson(),
            'trackerHost': _trackerHost,
            'trackerPort': _trackerPort,
          }),
        );
        await socket.flush();
        final line = await utf8.decoder
            .bind(socket)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(hours: 4));
        await socket.close();
        final response = jsonDecode(line) as Map<String, Object?>;
        if (response['ok'] == true) {
          stored++;
          onLog('Replica de ${video.name} armazenada em ${target.name}');
        } else {
          onLog(
            'Replica recusada por ${target.name}: ${response['error'] ?? 'erro'}',
          );
        }
      } on Object catch (error) {
        onLog('Falha ao replicar ${video.name} para ${target.name}: $error');
      }
    }
    return stored;
  }

  Future<File> downloadFromPeers({
    required List<PeerInfo> peers,
    required VideoItem video,
    required Directory outputDirectory,
    required ProgressWriter onProgress,
  }) async {
    if (peers.isEmpty) {
      throw StateError('Nenhum peer remoto disponivel para download.');
    }
    await outputDirectory.create(recursive: true);
    final finalFile = _targetFile(outputDirectory, video);
    final ranges = _buildRanges(
      totalBytes: video.size,
      partCount: min(peers.length, _maxParallelDownloads),
    );
    final partFiles = [
      for (var i = 0; i < ranges.length; i++) File('${finalFile.path}.part.$i'),
    ];
    final receivedByRange = List<int>.filled(ranges.length, 0);

    await _deleteIfExists(finalFile);
    for (final partFile in partFiles) {
      await _deleteIfExists(partFile);
    }

    void reportProgress(int index, int bytes) {
      receivedByRange[index] += bytes;
      final received = receivedByRange.fold<int>(0, (total, item) {
        return total + item;
      });
      onProgress(
        DownloadProgress(
          hash: video.hash,
          title: video.name,
          receivedBytes: received,
          totalBytes: video.size,
          status: ranges.length == 1
              ? 'baixando cifrado'
              : 'baixando ${ranges.length} partes',
        ),
      );
    }

    onLog(
      ranges.length == 1
          ? 'Download cifrado iniciado de ${peers.first.name}'
          : 'Download paralelo iniciado com ${ranges.length} peer(s)',
    );

    await Future.wait([
      for (var i = 0; i < ranges.length; i++)
        _downloadRange(
          connect: () => Socket.connect(
            peers[i % peers.length].host,
            peers[i % peers.length].port,
            timeout: const Duration(seconds: 8),
          ),
          request: {
            'type': 'GET_FILE',
            'hash': video.hash,
            'offset': ranges[i].start,
            'length': ranges[i].length,
            'encrypted': true,
          },
          range: ranges[i],
          partFile: partFiles[i],
          onBytes: (bytes) => reportProgress(i, bytes),
          sourceLabel: peers[i % peers.length].name,
        ),
    ]);

    await _joinParts(partFiles, finalFile);
    await _verifyDownloadedFile(finalFile, video);
    _mergeLibrary([
      VideoItem(
        name: video.name,
        hash: video.hash,
        size: video.size,
        localPath: finalFile.path,
      ),
    ]);
    onProgress(
      DownloadProgress(
        hash: video.hash,
        title: video.name,
        receivedBytes: video.size,
        totalBytes: video.size,
        status: 'concluido',
      ),
    );
    onLog('Download concluido e validado: ${video.name}');
    return finalFile;
  }

  Future<File> downloadViaTrackerRelay({
    required String trackerHost,
    required int trackerPort,
    required VideoItem video,
    required Directory outputDirectory,
    required ProgressWriter onProgress,
  }) async {
    await outputDirectory.create(recursive: true);
    final finalFile = _targetFile(outputDirectory, video);
    final partFile = File('${finalFile.path}.relay.part');
    final range = _DownloadRange(start: 0, length: video.size);
    var received = 0;

    await _deleteIfExists(finalFile);
    await _deleteIfExists(partFile);
    onLog('Tentando relay NAT pelo tracker para ${video.name}');

    await _downloadRange(
      connect: () => Socket.connect(
        trackerHost,
        trackerPort,
        timeout: const Duration(seconds: 8),
      ),
      request: {
        'type': 'RELAY_DOWNLOAD',
        'hash': video.hash,
        'requesterId': id,
        'offset': range.start,
        'length': range.length,
        'encrypted': true,
      },
      range: range,
      partFile: partFile,
      onBytes: (bytes) {
        received += bytes;
        onProgress(
          DownloadProgress(
            hash: video.hash,
            title: video.name,
            receivedBytes: received,
            totalBytes: video.size,
            status: 'relay cifrado',
          ),
        );
      },
      sourceLabel: 'tracker relay',
    );

    await partFile.rename(finalFile.path);
    await _verifyDownloadedFile(finalFile, video);
    _mergeLibrary([
      VideoItem(
        name: video.name,
        hash: video.hash,
        size: video.size,
        localPath: finalFile.path,
      ),
    ]);
    onProgress(
      DownloadProgress(
        hash: video.hash,
        title: video.name,
        receivedBytes: video.size,
        totalBytes: video.size,
        status: 'concluido',
      ),
    );
    onLog('Relay concluido e validado: ${video.name}');
    return finalFile;
  }

  Future<void> _downloadRange({
    required Future<Socket> Function() connect,
    required Map<String, Object?> request,
    required _DownloadRange range,
    required File partFile,
    required void Function(int bytes) onBytes,
    required String sourceLabel,
  }) async {
    final socket = await connect();
    final sink = partFile.openWrite();
    final completer = Completer<void>();
    var headerParsed = false;
    var headerBytes = <int>[];
    var received = 0;
    var failed = false;
    var encrypted = false;

    socket.write(encodeMessage(request));
    await socket.flush();

    void completeWithError(Object error) {
      failed = true;
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
      socket.destroy();
    }

    void writeBody(List<int> bytes) {
      if (bytes.isEmpty) {
        return;
      }
      final remaining = range.length - received;
      if (remaining <= 0) {
        return;
      }
      final body = bytes.length > remaining
          ? bytes.sublist(0, remaining)
          : bytes;
      final decoded = encrypted
          ? _xorCipher(body, absoluteOffset: range.start + received)
          : body;
      received += body.length;
      sink.add(decoded);
      onBytes(body.length);
    }

    socket.listen(
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
              StateError(
                header['error'] as String? ?? '$sourceLabel recusou o arquivo',
              ),
            );
            return;
          }
          encrypted = header['encrypted'] == true;
          headerParsed = true;
          writeBody(data.sublist(newline + 1));
          return;
        }
        writeBody(data);
      },
      onError: completeWithError,
      onDone: () async {
        await sink.close();
        if (failed) {
          return;
        }
        if (received != range.length) {
          completeWithError(
            StateError(
              '$sourceLabel enviou $received de ${range.length} bytes',
            ),
          );
          return;
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    return completer.future.timeout(const Duration(hours: 4));
  }

  Future<void> _handleUploadClient(Socket socket) async {
    try {
      final line = await utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      final request = jsonDecode(line) as Map<String, Object?>;
      if (request['type'] == 'HEARTBEAT') {
        socket.write(
          encodeMessage({'ok': true, 'type': 'HEARTBEAT_ACK', 'peerId': id}),
        );
        return;
      }
      if (request['type'] == 'STORE_REPLICA') {
        final response = await _storeReplica(request);
        socket.write(encodeMessage(response));
        return;
      }
      if (request['type'] == 'REPLICATE_RESOURCE') {
        final response = await _replicateResource(request);
        socket.write(encodeMessage(response));
        return;
      }
      if (request['type'] != 'GET_FILE') {
        socket.write(encodeMessage({'ok': false, 'error': 'Comando invalido'}));
        return;
      }
      final hash = request['hash'] as String? ?? '';
      final offset = (request['offset'] as num?)?.toInt() ?? 0;
      final requestedLength = (request['length'] as num?)?.toInt();
      final encrypted = request['encrypted'] == true;
      VideoItem? video;
      for (final item in _library) {
        if (item.hash == hash && item.isLocal) {
          video = item;
          break;
        }
      }
      if (video == null) {
        socket.write(
          encodeMessage({'ok': false, 'error': 'Arquivo nao encontrado'}),
        );
        return;
      }
      final file = File(video.localPath!);
      if (!await file.exists()) {
        socket.write(
          encodeMessage({'ok': false, 'error': 'Arquivo local indisponivel'}),
        );
        return;
      }
      if (offset < 0 || offset > video.size) {
        socket.write(encodeMessage({'ok': false, 'error': 'Offset invalido'}));
        return;
      }
      final available = video.size - offset;
      final length = min(requestedLength ?? available, available);
      socket.write(
        encodeMessage({
          'ok': true,
          'name': video.name,
          'size': video.size,
          'offset': offset,
          'length': length,
          'encrypted': encrypted,
          if (encrypted) 'cipher': transferCipherName,
        }),
      );
      await socket.flush();
      var sent = 0;
      final input = await file.open();
      try {
        await input.setPosition(offset);
        while (sent < length) {
          final nextSize = min(_transferBlockSize, length - sent);
          final chunk = await input.read(nextSize);
          if (chunk.isEmpty) {
            break;
          }
          final payload = encrypted
              ? _xorCipher(chunk, absoluteOffset: offset + sent)
              : chunk;
          socket.add(payload);
          sent += chunk.length;
        }
      } finally {
        await input.close();
      }
      await socket.flush();
      onLog(
        encrypted
            ? 'Upload cifrado concluido: ${video.name}'
            : 'Upload concluido: ${video.name}',
      );
    } on Object catch (error) {
      socket.write(encodeMessage({'ok': false, 'error': '$error'}));
    } finally {
      await socket.flush();
      await socket.close();
    }
  }

  Future<Map<String, Object?>> _storeReplica(
    Map<String, Object?> request,
  ) async {
    final storage = _storageDirectory;
    if (storage == null) {
      return {'ok': false, 'error': 'Diretorio de replicas nao configurado'};
    }
    final video = VideoItem.fromJson(
      (request['video'] as Map).cast<String, Object?>(),
    );
    if (localPathFor(video.hash) != null) {
      await _registerWithConfiguredTracker();
      return {'ok': true, 'stored': false, 'alreadyLocal': true};
    }
    final source = PeerInfo.fromJson(
      (request['source'] as Map).cast<String, Object?>(),
    );
    configure(
      trackerHost: request['trackerHost'] as String?,
      trackerPort: (request['trackerPort'] as num?)?.toInt(),
    );

    await downloadFromPeers(
      peers: [source],
      video: video,
      outputDirectory: storage,
      onProgress: (_) {},
    );
    await _registerWithConfiguredTracker();
    return {'ok': true, 'stored': true};
  }

  Future<Map<String, Object?>> _replicateResource(
    Map<String, Object?> request,
  ) async {
    final video = VideoItem.fromJson(
      (request['video'] as Map).cast<String, Object?>(),
    );
    if (localPathFor(video.hash) == null) {
      return {'ok': false, 'error': 'Arquivo local indisponivel'};
    }
    final targets = (request['targets'] as List? ?? [])
        .whereType<Map>()
        .map((item) => PeerInfo.fromJson(item.cast<String, Object?>()))
        .toList();
    final stored = await replicateVideoToPeers(video: video, targets: targets);
    return {'ok': stored == targets.length, 'stored': stored};
  }

  Future<void> _registerWithConfiguredTracker() async {
    final trackerHost = _trackerHost;
    final trackerPort = _trackerPort;
    final peerName = _peerName;
    final advertisedHost = _advertisedHost;
    final advertisedPort = _advertisedPort;
    if (trackerHost == null ||
        trackerPort == null ||
        peerName == null ||
        advertisedHost == null ||
        advertisedPort == null) {
      return;
    }
    await register(
      trackerHost: trackerHost,
      trackerPort: trackerPort,
      peerName: peerName,
      advertisedHost: advertisedHost,
      advertisedPort: advertisedPort,
    );
  }

  PeerInfo _selfInfo() {
    final peerName = _peerName;
    final advertisedHost = _advertisedHost;
    final advertisedPort = _advertisedPort;
    if (peerName == null || advertisedHost == null || advertisedPort == null) {
      throw StateError('Peer nao configurado para replicacao');
    }
    return PeerInfo(
      id: id,
      name: peerName,
      host: advertisedHost,
      port: advertisedPort,
      lastSeen: DateTime.now(),
    );
  }

  void _mergeLibrary(List<VideoItem> incoming) {
    final byHash = {for (final item in _library) item.hash: item};
    for (final item in incoming) {
      byHash[item.hash] = item;
    }
    _library = byHash.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  String? localPathFor(String hash) {
    for (final item in _library) {
      if (item.hash == hash && item.localPath != null) {
        return item.localPath;
      }
    }
    return null;
  }

  File _targetFile(Directory outputDirectory, VideoItem video) {
    final name = safeFileName(video.name);
    return File(
      '${outputDirectory.path}${Platform.pathSeparator}${name.isEmpty ? video.hash : name}',
    );
  }

  List<_DownloadRange> _buildRanges({
    required int totalBytes,
    required int partCount,
  }) {
    final safePartCount = max(
      1,
      min(partCount, totalBytes == 0 ? 1 : totalBytes),
    );
    final baseSize = totalBytes ~/ safePartCount;
    final remainder = totalBytes % safePartCount;
    final ranges = <_DownloadRange>[];
    var cursor = 0;
    for (var i = 0; i < safePartCount; i++) {
      final length = baseSize + (i < remainder ? 1 : 0);
      ranges.add(_DownloadRange(start: cursor, length: length));
      cursor += length;
    }
    return ranges;
  }

  Future<void> _joinParts(List<File> partFiles, File finalFile) async {
    final sink = finalFile.openWrite();
    for (final partFile in partFiles) {
      await sink.addStream(partFile.openRead());
      await partFile.delete();
    }
    await sink.close();
  }

  Future<void> _verifyDownloadedFile(File file, VideoItem video) async {
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != video.hash) {
      await _deleteIfExists(file);
      throw StateError('Hash invalido apos download de ${video.name}');
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _DownloadRange {
  const _DownloadRange({required this.start, required this.length});

  final int start;
  final int length;
}

List<int> _xorCipher(List<int> bytes, {required int absoluteOffset}) {
  final output = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    final position = absoluteOffset + i;
    final block = position ~/ 32;
    final blockOffset = position % 32;
    final keyBytes = sha256
        .convert(utf8.encode('$_simplePeerCipherKey:$block'))
        .bytes;
    output[i] = bytes[i] ^ keyBytes[blockOffset];
  }
  return output;
}

Future<Map<String, Object?>> requestTracker(
  String host,
  int port,
  Map<String, Object?> request,
) async {
  final socket = await Socket.connect(
    host,
    port,
    timeout: const Duration(seconds: 8),
  );
  socket.write(encodeMessage(request));
  await socket.flush();
  final line = await utf8.decoder
      .bind(socket)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 15));
  await socket.close();
  return (jsonDecode(line) as Map).cast<String, Object?>();
}
