import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'models.dart';

typedef ProgressWriter = void Function(DownloadProgress progress);
typedef LogWriter = void Function(String message);

class PeerNode {
  PeerNode({required this.onLog});

  final LogWriter onLog;
  final String id =
      'peer-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  ServerSocket? _uploadServer;
  List<VideoItem> _library = [];

  List<VideoItem> get library => List.unmodifiable(_library);
  bool get isServing => _uploadServer != null;

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

  Future<File> downloadFromPeer({
    required PeerInfo peer,
    required VideoItem video,
    required Directory outputDirectory,
    required ProgressWriter onProgress,
  }) async {
    await outputDirectory.create(recursive: true);
    final extension = _extensionOf(video.name);
    final target = File(
      '${outputDirectory.path}${Platform.pathSeparator}${safeFileName(video.name)}-$extension.part',
    );
    final finalFile = File(
      '${outputDirectory.path}${Platform.pathSeparator}${safeFileName(video.name)}',
    );
    final socket = await Socket.connect(
      peer.host,
      peer.port,
      timeout: const Duration(seconds: 8),
    );
    final sink = target.openWrite();
    final completer = Completer<File>();
    var headerParsed = false;
    var headerBytes = <int>[];
    var received = 0;
    var total = video.size;
    var failed = false;

    socket.write(encodeMessage({'type': 'GET_FILE', 'hash': video.hash}));

    void writeBody(List<int> bytes) {
      if (bytes.isEmpty) {
        return;
      }
      received += bytes.length;
      sink.add(bytes);
      onProgress(
        DownloadProgress(
          hash: video.hash,
          title: video.name,
          receivedBytes: received,
          totalBytes: total,
          status: 'baixando',
        ),
      );
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
            failed = true;
            completer.completeError(
              StateError(
                header['error'] as String? ?? 'Peer recusou o arquivo',
              ),
            );
            socket.destroy();
            return;
          }
          total = (header['size'] as num?)?.toInt() ?? total;
          headerParsed = true;
          writeBody(data.sublist(newline + 1));
          return;
        }
        writeBody(data);
      },
      onError: (Object error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () async {
        await sink.close();
        if (failed) {
          return;
        }
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await target.rename(finalFile.path);
        _mergeLibrary([
          VideoItem(
            name: video.name,
            hash: video.hash,
            size: total,
            localPath: finalFile.path,
          ),
        ]);
        onProgress(
          DownloadProgress(
            hash: video.hash,
            title: video.name,
            receivedBytes: total,
            totalBytes: total,
            status: 'concluido',
          ),
        );
        if (!completer.isCompleted) {
          completer.complete(finalFile);
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
      if (request['type'] != 'GET_FILE') {
        socket.write(encodeMessage({'ok': false, 'error': 'Comando invalido'}));
        return;
      }
      final hash = request['hash'] as String? ?? '';
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
      socket.write(
        encodeMessage({'ok': true, 'name': video.name, 'size': video.size}),
      );
      await socket.flush();
      await file.openRead().pipe(socket);
      onLog('Upload concluido: ${video.name}');
    } on Object catch (error) {
      socket.write(encodeMessage({'ok': false, 'error': '$error'}));
      await socket.flush();
      await socket.close();
    }
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

  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) {
      return 'video';
    }
    return name.substring(dot + 1);
  }
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
