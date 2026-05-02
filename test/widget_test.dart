import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_party/main.dart';

void main() {
  testWidgets('abre a interface principal da festa P2P', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoPartyApp());

    expect(find.text('Video Party P2P'), findsOneWidget);
    expect(find.text('Iniciar tracker'), findsOneWidget);
    expect(find.text('Pasta de videos'), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.cloud_download_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Padrao'), findsOneWidget);
    expect(find.text('Branco'), findsOneWidget);
    expect(find.text('Sistema'), findsOneWidget);
  });
}
