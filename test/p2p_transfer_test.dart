import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_party/models.dart';
import 'package:video_party/peer_node.dart';
import 'package:video_party/tracker_server.dart';

void main() {
  test('baixa arquivo em partes paralelas com trafego cifrado', () async {
    final root = await Directory.systemTemp.createTemp('video_party_p2p_');
    final sourceA = Directory('${root.path}${Platform.pathSeparator}a');
    final sourceB = Directory('${root.path}${Platform.pathSeparator}b');
    final output = Directory('${root.path}${Platform.pathSeparator}out');
    final bytes = List<int>.generate(4097, (index) => (index * 31) % 256);

    try {
      await sourceA.create();
      await sourceB.create();
      await File(
        '${sourceA.path}${Platform.pathSeparator}clip.mp4',
      ).writeAsBytes(bytes);
      await File(
        '${sourceB.path}${Platform.pathSeparator}clip.mp4',
      ).writeAsBytes(bytes);

      final portA = await _freePort();
      final portB = await _freePort();
      final ownerA = PeerNode(onLog: (_) {});
      final ownerB = PeerNode(onLog: (_) {});
      final downloader = PeerNode(onLog: (_) {});

      await ownerA.scanFolder(sourceA.path);
      await ownerB.scanFolder(sourceB.path);
      await ownerA.startUploadServer(host: '127.0.0.1', port: portA);
      await ownerB.startUploadServer(host: '127.0.0.1', port: portB);

      final video = ownerA.library.single;
      final downloaded = await downloader.downloadFromPeers(
        peers: [
          _peerInfo(ownerA, portA, 'owner-a'),
          _peerInfo(ownerB, portB, 'owner-b'),
        ],
        video: video,
        outputDirectory: output,
        onProgress: (_) {},
      );

      expect(await downloaded.readAsBytes(), bytes);

      await ownerA.stopUploadServer();
      await ownerB.stopUploadServer();
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('usa relay do tracker quando solicitado', () async {
    final root = await Directory.systemTemp.createTemp('video_party_relay_');
    final source = Directory('${root.path}${Platform.pathSeparator}source');
    final output = Directory('${root.path}${Platform.pathSeparator}out');
    final bytes = List<int>.generate(2049, (index) => (index * 17) % 256);

    final owner = PeerNode(onLog: (_) {});
    final downloader = PeerNode(onLog: (_) {});
    final tracker = TrackerServer(onLog: (_) {}, onChanged: () {});

    try {
      await source.create();
      await File(
        '${source.path}${Platform.pathSeparator}relay.mp4',
      ).writeAsBytes(bytes);

      final ownerPort = await _freePort();
      final trackerPort = await _freePort();
      await owner.scanFolder(source.path);
      await owner.startUploadServer(host: '127.0.0.1', port: ownerPort);
      await tracker.start(host: '127.0.0.1', port: trackerPort);
      await owner.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'owner',
        advertisedHost: '127.0.0.1',
        advertisedPort: ownerPort,
      );
      final lookup = await requestTracker('127.0.0.1', trackerPort, {
        'type': 'LOOKUP',
        'name': 'relay.mp4',
      });

      expect(lookup['ok'], isTrue);
      expect((lookup['video'] as Map)['name'], 'relay.mp4');
      expect((lookup['peers'] as List), hasLength(1));

      final downloaded = await downloader.downloadViaTrackerRelay(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        video: owner.library.single,
        outputDirectory: output,
        onProgress: (_) {},
      );

      expect(await downloaded.readAsBytes(), bytes);
    } finally {
      await owner.stopUploadServer();
      await tracker.stop();
      await root.delete(recursive: true);
    }
  });

  test('tracker remove peers que nao respondem heartbeat', () async {
    final root = await Directory.systemTemp.createTemp(
      'video_party_heartbeat_',
    );
    final source = Directory('${root.path}${Platform.pathSeparator}source');
    final bytes = List<int>.generate(128, (index) => index % 256);
    var watchingRemoval = false;
    final removed = Completer<void>();

    final owner = PeerNode(onLog: (_) {});
    final tracker = TrackerServer(
      onLog: (_) {},
      onChanged: () {
        if (watchingRemoval && !removed.isCompleted) {
          removed.complete();
        }
      },
      heartbeatInterval: const Duration(milliseconds: 100),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );

    try {
      await source.create();
      await File(
        '${source.path}${Platform.pathSeparator}dead-peer.mp4',
      ).writeAsBytes(bytes);

      final ownerPort = await _freePort();
      final trackerPort = await _freePort();
      await owner.scanFolder(source.path);
      await owner.startUploadServer(host: '127.0.0.1', port: ownerPort);
      await tracker.start(host: '127.0.0.1', port: trackerPort);
      await owner.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'owner',
        advertisedHost: '127.0.0.1',
        advertisedPort: ownerPort,
      );

      var response = await requestTracker('127.0.0.1', trackerPort, {
        'type': 'LIST',
      });
      var snapshot = TrackerSnapshot.fromJson(
        (response['snapshot'] as Map).cast<String, Object?>(),
      );
      expect(snapshot.peers, hasLength(1));
      expect(snapshot.videos, hasLength(1));

      watchingRemoval = true;
      await owner.stopUploadServer();
      await removed.future.timeout(const Duration(seconds: 3));

      response = await requestTracker('127.0.0.1', trackerPort, {
        'type': 'LIST',
      });
      snapshot = TrackerSnapshot.fromJson(
        (response['snapshot'] as Map).cast<String, Object?>(),
      );
      expect(snapshot.peers, isEmpty);
      expect(snapshot.videos, isEmpty);
    } finally {
      await owner.stopUploadServer();
      await tracker.stop();
      await root.delete(recursive: true);
    }
  });

  test('tracker responde WHEREIS, SEARCH e UNREGISTER', () async {
    final root = await Directory.systemTemp.createTemp('video_party_whereis_');
    final source = Directory('${root.path}${Platform.pathSeparator}source');
    final owner = PeerNode(onLog: (_) {});
    final tracker = TrackerServer(onLog: (_) {}, onChanged: () {});

    try {
      await source.create();
      await File(
        '${source.path}${Platform.pathSeparator}aula-redes.mp4',
      ).writeAsBytes(List<int>.generate(256, (index) => index % 256));

      final ownerPort = await _freePort();
      final trackerPort = await _freePort();
      _configurePeer(owner, root, trackerPort, ownerPort, 'owner');
      await owner.scanFolder(source.path);
      await owner.startUploadServer(host: '127.0.0.1', port: ownerPort);
      await tracker.start(host: '127.0.0.1', port: trackerPort);
      await owner.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'owner',
        advertisedHost: '127.0.0.1',
        advertisedPort: ownerPort,
      );

      final whereis = await _rawTrackerRequest(
        trackerPort,
        'WHEREIS aula-redes.mp4',
      );
      expect(whereis['ok'], isTrue);
      expect((whereis['peers'] as List), hasLength(1));

      final search = await requestTracker('127.0.0.1', trackerPort, {
        'type': 'SEARCH',
        'query': 'redes',
      });
      expect(search['ok'], isTrue);
      expect((search['results'] as List), hasLength(1));

      await owner.unregister(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
      );
      final listed = await requestTracker('127.0.0.1', trackerPort, {
        'type': 'LIST',
      });
      final snapshot = TrackerSnapshot.fromJson(
        (listed['snapshot'] as Map).cast<String, Object?>(),
      );
      expect(snapshot.peers, isEmpty);
      expect(snapshot.videos, isEmpty);
    } finally {
      await owner.stopUploadServer();
      await tracker.stop();
      await root.delete(recursive: true);
    }
  });

  test('publicacao replica arquivo voluntariamente em dois peers', () async {
    final root = await Directory.systemTemp.createTemp('video_party_replica_');
    final source = Directory('${root.path}${Platform.pathSeparator}source');
    final bytes = List<int>.generate(3073, (index) => (index * 13) % 256);

    final owner = PeerNode(onLog: (_) {});
    final replicaA = PeerNode(onLog: (_) {});
    final replicaB = PeerNode(onLog: (_) {});
    final tracker = TrackerServer(onLog: (_) {}, onChanged: () {});

    try {
      await source.create();
      await File(
        '${source.path}${Platform.pathSeparator}trabalho-final.mp4',
      ).writeAsBytes(bytes);

      final trackerPort = await _freePort();
      final ownerPort = await _freePort();
      final replicaAPort = await _freePort();
      final replicaBPort = await _freePort();

      _configurePeer(owner, root, trackerPort, ownerPort, 'owner');
      _configurePeer(replicaA, root, trackerPort, replicaAPort, 'replica-a');
      _configurePeer(replicaB, root, trackerPort, replicaBPort, 'replica-b');

      await tracker.start(host: '127.0.0.1', port: trackerPort);
      await owner.startUploadServer(host: '127.0.0.1', port: ownerPort);
      await replicaA.startUploadServer(host: '127.0.0.1', port: replicaAPort);
      await replicaB.startUploadServer(host: '127.0.0.1', port: replicaBPort);
      await replicaA.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'replica-a',
        advertisedHost: '127.0.0.1',
        advertisedPort: replicaAPort,
      );
      await replicaB.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'replica-b',
        advertisedHost: '127.0.0.1',
        advertisedPort: replicaBPort,
      );
      await owner.scanFolder(source.path);
      await owner.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'owner',
        advertisedHost: '127.0.0.1',
        advertisedPort: ownerPort,
      );

      final stored = await owner.ensureReplication(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
      );

      expect(stored, 2);
      final video = owner.library.single;
      expect(replicaA.localPathFor(video.hash), isNotNull);
      expect(replicaB.localPathFor(video.hash), isNotNull);
      expect(
        await File(replicaA.localPathFor(video.hash)!).readAsBytes(),
        bytes,
      );
      expect(
        await File(replicaB.localPathFor(video.hash)!).readAsBytes(),
        bytes,
      );

      final lookup = await requestTracker('127.0.0.1', trackerPort, {
        'type': 'LOOKUP',
        'hash': video.hash,
      });
      expect((lookup['peers'] as List), hasLength(3));
    } finally {
      await owner.stopUploadServer();
      await replicaA.stopUploadServer();
      await replicaB.stopUploadServer();
      await tracker.stop();
      await root.delete(recursive: true);
    }
  });

  test('tracker re-replica quando uma replica cai', () async {
    final root = await Directory.systemTemp.createTemp('video_party_repair_');
    final source = Directory('${root.path}${Platform.pathSeparator}source');
    final bytes = List<int>.generate(4099, (index) => (index * 19) % 256);

    final owner = PeerNode(onLog: (_) {});
    final replicaA = PeerNode(onLog: (_) {});
    final replicaB = PeerNode(onLog: (_) {});
    final spare = PeerNode(onLog: (_) {});
    final tracker = TrackerServer(
      onLog: (_) {},
      onChanged: () {},
      heartbeatInterval: const Duration(milliseconds: 100),
      heartbeatTimeout: const Duration(milliseconds: 100),
    );

    try {
      await source.create();
      await File(
        '${source.path}${Platform.pathSeparator}backup.mp4',
      ).writeAsBytes(bytes);

      final trackerPort = await _freePort();
      final ownerPort = await _freePort();
      final replicaAPort = await _freePort();
      final replicaBPort = await _freePort();
      final sparePort = await _freePort();

      _configurePeer(owner, root, trackerPort, ownerPort, 'owner');
      _configurePeer(replicaA, root, trackerPort, replicaAPort, 'replica-a');
      _configurePeer(replicaB, root, trackerPort, replicaBPort, 'replica-b');
      _configurePeer(spare, root, trackerPort, sparePort, 'spare');

      await tracker.start(host: '127.0.0.1', port: trackerPort);
      await owner.startUploadServer(host: '127.0.0.1', port: ownerPort);
      await replicaA.startUploadServer(host: '127.0.0.1', port: replicaAPort);
      await replicaB.startUploadServer(host: '127.0.0.1', port: replicaBPort);
      await spare.startUploadServer(host: '127.0.0.1', port: sparePort);

      await replicaA.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'replica-a',
        advertisedHost: '127.0.0.1',
        advertisedPort: replicaAPort,
      );
      await replicaB.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'replica-b',
        advertisedHost: '127.0.0.1',
        advertisedPort: replicaBPort,
      );
      await spare.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'spare',
        advertisedHost: '127.0.0.1',
        advertisedPort: sparePort,
      );
      await owner.scanFolder(source.path);
      await owner.register(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
        peerName: 'owner',
        advertisedHost: '127.0.0.1',
        advertisedPort: ownerPort,
      );
      await owner.ensureReplication(
        trackerHost: '127.0.0.1',
        trackerPort: trackerPort,
      );

      final video = owner.library.single;
      await replicaA.stopUploadServer();

      await _waitFor(() async {
        final lookup = await requestTracker('127.0.0.1', trackerPort, {
          'type': 'LOOKUP',
          'hash': video.hash,
        });
        final peers = (lookup['peers'] as List)
            .whereType<Map>()
            .map((item) => item['id'])
            .toSet();
        return peers.length == 3 &&
            peers.contains(owner.id) &&
            peers.contains(replicaB.id) &&
            peers.contains(spare.id);
      });

      expect(spare.localPathFor(video.hash), isNotNull);
      expect(await File(spare.localPathFor(video.hash)!).readAsBytes(), bytes);
    } finally {
      await owner.stopUploadServer();
      await replicaA.stopUploadServer();
      await replicaB.stopUploadServer();
      await spare.stopUploadServer();
      await tracker.stop();
      await root.delete(recursive: true);
    }
  });
}

PeerInfo _peerInfo(PeerNode peer, int port, String name) {
  return PeerInfo(
    id: peer.id,
    name: name,
    host: '127.0.0.1',
    port: port,
    lastSeen: DateTime.now(),
  );
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void _configurePeer(
  PeerNode peer,
  Directory root,
  int trackerPort,
  int peerPort,
  String name,
) {
  peer.configure(
    storageDirectory: Directory('${root.path}${Platform.pathSeparator}$name'),
    trackerHost: '127.0.0.1',
    trackerPort: trackerPort,
    peerName: name,
    advertisedHost: '127.0.0.1',
    advertisedPort: peerPort,
  );
}

Future<Map<String, Object?>> _rawTrackerRequest(int port, String line) async {
  final socket = await Socket.connect(
    '127.0.0.1',
    port,
    timeout: const Duration(seconds: 8),
  );
  socket.write('$line\n');
  await socket.flush();
  final response = await utf8.decoder
      .bind(socket)
      .transform(const LineSplitter())
      .first
      .timeout(const Duration(seconds: 15));
  await socket.close();
  return (jsonDecode(response) as Map).cast<String, Object?>();
}

Future<void> _waitFor(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Condicao nao atendida dentro do prazo');
}
