# Video Party P2P - Release

## Destaques

- App Android adaptativo com navegacao inferior e telas separadas para Inicio, Player, Downloads e Config.
- Nova paleta visual escura com acento violeta e icone atualizado em Android, Windows, macOS e Web.
- Pasta de videos unificada: a mesma pasta selecionada e usada para mapear, baixar, compartilhar e semear arquivos.
- Downloads concluidos passam a entrar na biblioteca local e podem ser baixados por outros peers.
- Download P2P em partes paralelas a partir de multiplos peers, com fallback via relay do tracker.
- Seletor de pasta integrado na configuracao.

## Artefatos

- Windows: `windows/video_party_windows_release.zip`
- Android APK: `android/video_party_android_release.apk`
- Android App Bundle: `android/video_party_android_release.aab`

## Validacao

- `flutter analyze`
- `flutter test`
- `flutter build windows --release`
- `flutter build apk --release`
- `flutter build appbundle --release`
