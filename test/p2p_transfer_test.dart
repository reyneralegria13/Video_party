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
