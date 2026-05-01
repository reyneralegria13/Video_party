# Video Party P2P

Aplicativo Flutter para a disciplina de Sistemas Distribuidos. Ele implementa uma arquitetura P2P hibrida para uma festa colaborativa de videos:

- Um tracker TCP guarda metadados, peers e a playlist global.
- Cada cliente Flutter tambem atua como servidor de upload TCP.
- Downloads acontecem diretamente entre peers, sem passar os bytes pelo tracker.
- Ao reproduzir um item da playlist, o app inicia prefetch do proximo video em segundo plano.

## Como rodar

Use desktop, pois o projeto usa `dart:io` para sockets TCP e arquivos locais.

```bash
flutter pub get
flutter run -d windows
```

No Linux:

```bash
flutter run -d linux
```

## Teste em duas maquinas

1. Instale e conecte as duas maquinas no Tailscale.
2. Na maquina A, abra o app e clique em **Iniciar tracker**.
3. Ainda na maquina A, informe:
   - `Meu IP/Tailscale`: IP `100.x.x.x` da maquina A.
   - `Pasta de videos`: pasta com arquivos `.mp4`, `.mkv`, `.webm`, `.avi`, `.mov` ou `.m4v`.
4. Clique em **Ativar upload** e depois **Escanear e registrar**.
5. Na maquina B, informe:
   - `Tracker IP`: IP Tailscale da maquina A.
   - `Meu IP/Tailscale`: IP Tailscale da maquina B.
   - `Pasta de videos`: outra pasta local, se houver.
6. Na maquina B, clique em **Ativar upload**, **Escanear e registrar** e **Atualizar rede**.
7. Qualquer peer pode adicionar videos ao **Catalogo global** para montar a **Playlist global**.
8. Ao tocar um video, o app baixa o atual se necessario e faz prefetch do proximo item.

Os arquivos baixados ficam em `VideoPartyDownloads` dentro da pasta do usuario.

## Protocolo JSON/TCP

Cada comando de controle e uma linha JSON terminada por `\n`.

### Tracker

`REGISTER`

```json
{
  "type": "REGISTER",
  "peer": {"id": "peer-1", "name": "DJ Video", "host": "100.x.x.x", "port": 5051},
  "videos": [{"name": "show.mp4", "hash": "sha256", "size": 104857600}]
}
```

`LIST`

```json
{"type": "LIST"}
```

`ADD_PLAYLIST`

```json
{"type": "ADD_PLAYLIST", "hash": "sha256", "title": "show.mp4", "peerName": "DJ Video"}
```

`DOWNLOAD` ou `LOOKUP`

```json
{"type": "DOWNLOAD", "hash": "sha256"}
```

### Peer

O download direto usa `GET_FILE`. O peer responde primeiro com um cabecalho JSON e depois envia os bytes crus do arquivo no mesmo socket.

```json
{"type": "GET_FILE", "hash": "sha256"}
```

Resposta:

```json
{"ok": true, "name": "show.mp4", "size": 104857600}
```

## Validacao

```bash
flutter analyze
flutter test
```
