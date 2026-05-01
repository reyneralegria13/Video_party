import 'dart:convert';
import 'dart:io';

const videoExtensions = {'.mp4', '.mkv', '.webm', '.avi', '.mov', '.m4v'};
const transferCipherName = 'xor-sha256-demo';

class VideoItem {
  const VideoItem({
    required this.name,
    required this.hash,
    required this.size,
    this.localPath,
  });

  final String name;
  final String hash;
  final int size;
  final String? localPath;

  bool get isLocal => localPath != null;

  Map<String, Object?> toJson({bool includePath = false}) => {
    'name': name,
    'hash': hash,
    'size': size,
    if (includePath) 'localPath': localPath,
  };

  factory VideoItem.fromJson(Map<String, Object?> json) => VideoItem(
    name: json['name'] as String? ?? 'video-sem-nome',
    hash: json['hash'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    localPath: json['localPath'] as String?,
  );
}

class PeerInfo {
  const PeerInfo({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final DateTime lastSeen;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'lastSeen': lastSeen.toIso8601String(),
  };

  factory PeerInfo.fromJson(Map<String, Object?> json) => PeerInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'peer',
    host: json['host'] as String? ?? '127.0.0.1',
    port: (json['port'] as num?)?.toInt() ?? 0,
    lastSeen:
        DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
  );
}

class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.hash,
    required this.title,
    required this.addedBy,
    required this.addedAt,
  });

  final String id;
  final String hash;
  final String title;
  final String addedBy;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'hash': hash,
    'title': title,
    'addedBy': addedBy,
    'addedAt': addedAt.toIso8601String(),
  };

  factory PlaylistEntry.fromJson(Map<String, Object?> json) => PlaylistEntry(
    id: json['id'] as String? ?? '',
    hash: json['hash'] as String? ?? '',
    title: json['title'] as String? ?? 'video',
    addedBy: json['addedBy'] as String? ?? 'peer',
    addedAt:
        DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class TrackerSnapshot {
  const TrackerSnapshot({
    required this.videos,
    required this.peers,
    required this.playlist,
  });

  final List<VideoItem> videos;
  final List<PeerInfo> peers;
  final List<PlaylistEntry> playlist;

  factory TrackerSnapshot.empty() =>
      const TrackerSnapshot(videos: [], peers: [], playlist: []);

  factory TrackerSnapshot.fromJson(Map<String, Object?> json) {
    final videos = (json['videos'] as List? ?? [])
        .whereType<Map>()
        .map((item) => VideoItem.fromJson(item.cast<String, Object?>()))
        .toList();
    final peers = (json['peers'] as List? ?? [])
        .whereType<Map>()
        .map((item) => PeerInfo.fromJson(item.cast<String, Object?>()))
        .toList();
    final playlist = (json['playlist'] as List? ?? [])
        .whereType<Map>()
        .map((item) => PlaylistEntry.fromJson(item.cast<String, Object?>()))
        .toList();
    return TrackerSnapshot(videos: videos, peers: peers, playlist: playlist);
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.hash,
    required this.title,
    required this.receivedBytes,
    required this.totalBytes,
    required this.status,
  });

  final String hash;
  final String title;
  final int receivedBytes;
  final int totalBytes;
  final String status;

  double get progress {
    if (totalBytes <= 0) {
      return status == 'concluido' ? 1 : 0;
    }
    return (receivedBytes / totalBytes).clamp(0, 1);
  }
}

String encodeMessage(Map<String, Object?> message) =>
    '${jsonEncode(message)}\n';

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

String safeFileName(String value) => value
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool isVideoFile(FileSystemEntity entity) {
  if (entity is! File) {
    return false;
  }
  final path = entity.path.toLowerCase();
  return videoExtensions.any(path.endsWith);
}
