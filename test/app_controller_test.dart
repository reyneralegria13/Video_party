import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_party/app_controller.dart';

void main() {
  test('usa a pasta de videos como destino dos downloads', () async {
    final root = await Directory.systemTemp.createTemp(
      'video_party_controller_',
    );
    final videos = Directory('${root.path}${Platform.pathSeparator}videos');

    try {
      await videos.create();
      final controller = AppController();
      addTearDown(controller.dispose);

      expect(controller.downloadFolder, 'Selecione a pasta de videos');

      controller.updateConfig(folderPath: videos.path);

      expect(controller.downloadFolder, videos.path);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
