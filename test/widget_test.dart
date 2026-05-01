import 'package:flutter_test/flutter_test.dart';
import 'package:video_party/main.dart';

void main() {
  testWidgets('abre a interface principal da festa P2P', (tester) async {
    await tester.pumpWidget(const VideoPartyApp());

    expect(find.text('Video Party P2P'), findsOneWidget);
    expect(find.text('Iniciar tracker'), findsOneWidget);
    expect(find.text('Pasta de videos'), findsOneWidget);
  });
}
