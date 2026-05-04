# Video Party P2P

Aplicativo Flutter para a disciplina de Sistemas Distribuidos. Ele implementa uma arquitetura P2P hibrida para uma festa colaborativa de videos:

- Um tracker TCP guarda metadados, peers e a playlist global.
- Cada cliente Flutter tambem atua como servidor de upload TCP.
- Downloads acontecem diretamente entre peers e podem ser divididos em partes paralelas.
- O trafego de arquivo entre peers usa uma cifra simples `xor-sha256-demo` para fins didaticos.
- Se o acesso direto falhar, o app tenta um relay de download pelo tracker.
- Ao publicar arquivos, o peer tenta criar replicas voluntarias em outros 2 peers disponiveis.
- Se uma replica cair, o heartbeat do tracker remove o peer e solicita re-replicacao para manter o numero de copias.
- Ao reproduzir um item da playlist, o app toca o arquivo local com `media_kit` e inicia prefetch do proximo video em segundo plano.
- A interface permite escolher entre tema padrao escuro, tema branco ou tema seguindo o sistema.

## Identidade visual

O icone do app representa uma tela de video com um play central, tres nos conectados para simbolizar tracker/peers e cores neon para reforcar a ideia de uma festa colaborativa. A arte base fica em `assets/brand/video_party_icon.svg`, e os assets de Windows, macOS e web sao gerados por `tool/generate_app_icons.py`.

## Como rodar

Use desktop, pois o projeto usa `dart:io` para sockets TCP e arquivos locais.

```bash
flutter pub get
flutter run -d windows
```

No Windows, habilite o Modo Desenvolvedor se o Flutter pedir suporte a symlinks para plugins nativos:

```powershell
start ms-settings:developers
```

No Linux:

```bash
flutter run -d linux
```

## Executar a release no Linux

Baixe `VideoParty-linux-x64.tar.gz` na pagina de releases e extraia o pacote:

```bash
tar -xzf VideoParty-linux-x64.tar.gz
cd bundle
./video_party
```

Se o Linux bloquear a execucao, marque o binario como executavel:

```bash
chmod +x video_party
./video_party
```

Em distribuicoes baseadas em Ubuntu/Debian, instale as dependencias de runtime se o app nao abrir por falta de biblioteca nativa:

```bash
sudo apt-get update
sudo apt-get install -y libgtk-3-0 libmpv2
```

## Teste em rede local ou Tailscale

O app funciona em rede local pelo roteador, sem Tailscale, desde que as maquinas estejam na mesma rede Wi-Fi/cabo e o firewall permita conexoes TCP nas portas usadas pelo app. Nao precisa configurar port forwarding no roteador para usar dentro da mesma rede local.

Para usar pela rede local, substitua os IPs `100.x.x.x` do Tailscale pelos IPs locais das maquinas, por exemplo `192.168.0.23` ou `192.168.1.50`. No Windows, descubra o IP com `ipconfig`. No Linux, use `ip addr` ou `hostname -I`.

### Maquina A como tracker

1. Abra o app na maquina A.
2. Em `Meu IP/Tailscale`, informe o IP local da maquina A, por exemplo `192.168.0.23`.
3. Em `Tracker IP`, informe o mesmo IP da maquina A.
4. Deixe a porta do tracker como `4040`, salvo se quiser usar outra.
5. Deixe a porta de upload como `5051`, salvo se quiser usar outra.
6. Escolha a **Pasta de videos**.
7. Clique em **Iniciar tracker**.
8. Clique em **Ativar upload**.
9. Clique em **Escanear e registrar**.

### Outras maquinas na rede

1. Abra o app na maquina B, C ou outra maquina da rede.
2. Em `Tracker IP`, informe o IP local da maquina A, por exemplo `192.168.0.23`.
3. Em `Meu IP/Tailscale`, informe o IP local da propria maquina, por exemplo `192.168.0.31`.
4. Use a mesma porta do tracker configurada na maquina A, normalmente `4040`.
5. Use uma porta de upload livre nessa maquina, normalmente `5051`.
6. Escolha a **Pasta de videos**.
7. Clique em **Ativar upload**.
8. Clique em **Escanear e registrar**.
9. Clique em **Atualizar rede**.

Se as maquinas nao se enxergarem, libere no firewall as portas TCP `4040` e `5051` nas maquinas que recebem conexoes. Se varios peers rodarem na mesma maquina, use portas de upload diferentes para cada instancia.

## Teste em duas maquinas com Tailscale

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
7. Para demonstrar replicacao voluntaria, deixe ao menos tres peers registrados antes de publicar uma pasta com videos. Ao registrar, o dono tenta copiar cada arquivo para outros 2 peers.
8. Qualquer peer pode adicionar videos ao **Catalogo global** para montar a **Playlist global**.
9. Ao tocar um video, o app baixa o atual se necessario e faz prefetch do proximo item.
10. Depois do download, o player embutido reproduz o arquivo local na area principal.

Os arquivos baixados ficam em `VideoPartyDownloads` dentro da pasta do usuario.

## Mapeamento dos comandos do trabalho

A entrega usa GUI, mas os comandos da rubrica existem como acoes/protocolo:

- `publish <caminho_do_arquivo>`: informe a pasta em **Pasta de videos** e clique em **Escanear e registrar**. O registro publica os arquivos e tenta replicar em outros 2 peers.
- `search <palavra>`: protocolo `SEARCH`, que busca por substring no tracker.
- `WHEREIS <nome_do_recurso>`: protocolo textual aceito pelo tracker e alias JSON `WHEREIS`.
- `download <nome_do_recurso> <ip:porta_do_peer>`: o app baixa direto por `GET_FILE` via TCP. Se o peer cair, reconsulta o tracker, tenta outro peer e depois usa relay.
- `list_local`: a biblioteca local aparece no painel **Biblioteca local**.
- `exit`: ao fechar, o cliente envia `UNREGISTER`; se a saida for abrupta, o heartbeat remove o peer.

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

`UNREGISTER`

```json
{"type": "UNREGISTER", "peerId": "peer-1"}
```

`WHEREIS`

Formato textual:

```text
WHEREIS show.mp4
```

Formato JSON:

```json
{"type": "WHEREIS", "name": "show.mp4"}
```

`SEARCH`

```json
{"type": "SEARCH", "query": "show"}
```

`ADD_PLAYLIST`

```json
{"type": "ADD_PLAYLIST", "hash": "sha256", "title": "show.mp4", "peerName": "DJ Video"}
```

`DOWNLOAD` ou `LOOKUP` por hash

```json
{"type": "DOWNLOAD", "hash": "sha256"}
```

`LOOKUP` por nome

Compatibilidade com o formato textual do trabalho (`LOOKUP <nome>`), usando JSON/TCP:

```json
{"type": "LOOKUP", "name": "show.mp4"}
```

Resposta:

```json
{"ok": true, "video": {"name": "show.mp4", "hash": "sha256", "size": 104857600}, "peers": [{"id": "peer-1", "name": "DJ Video", "host": "100.x.x.x", "port": 5051}]}
```

`RELAY_DOWNLOAD`

Usado como fallback quando um peer nao consegue abrir conexao direta com outro. O tracker conecta em um owner alcancavel e repassa os bytes para o solicitante.

```json
{"type": "RELAY_DOWNLOAD", "hash": "sha256", "requesterId": "peer-2", "offset": 0, "length": 1048576, "encrypted": true}
```

O tracker tambem envia `HEARTBEAT` periodicamente aos peers registrados. Quem nao responder com `HEARTBEAT_ACK` e removido da lista de peers e deixa de aparecer como owner dos videos.
Quando um recurso fica com menos copias do que o alvo possivel na rede, o tracker envia `REPLICATE_RESOURCE` para um owner ativo.

### Peer

`HEARTBEAT`

```json
{"type": "HEARTBEAT", "peerId": "peer-1"}
```

Resposta:

```json
{"ok": true, "type": "HEARTBEAT_ACK", "peerId": "peer-1"}
```

O download direto usa `GET_FILE`. O peer responde primeiro com um cabecalho JSON e depois envia os bytes do intervalo pedido no mesmo socket.

```json
{"type": "GET_FILE", "hash": "sha256", "offset": 0, "length": 1048576, "encrypted": true}
```

Resposta:

```json
{"ok": true, "name": "show.mp4", "size": 104857600, "offset": 0, "length": 1048576, "encrypted": true, "cipher": "xor-sha256-demo"}
```

O peer envia o arquivo em blocos de ate 1024 bytes. O cliente divide o arquivo em ate quatro partes, baixa de peers diferentes quando disponiveis, remonta o arquivo localmente e valida o SHA-256 final antes de registrar o novo owner no tracker.

`STORE_REPLICA`

Um peer owner pede a outro peer para guardar uma replica. O peer destino puxa o arquivo do owner via `GET_FILE`, salva em `VideoPartyDownloads` e registra a nova copia no tracker.

```json
{
  "type": "STORE_REPLICA",
  "video": {"name": "show.mp4", "hash": "sha256", "size": 104857600},
  "source": {"id": "peer-1", "name": "DJ Video", "host": "100.x.x.x", "port": 5051},
  "trackerHost": "100.x.x.x",
  "trackerPort": 4040
}
```

`REPLICATE_RESOURCE`

Usado pelo tracker para reparar replicas apos falha detectada por heartbeat.

```json
{
  "type": "REPLICATE_RESOURCE",
  "video": {"name": "show.mp4", "hash": "sha256", "size": 104857600},
  "targets": [{"id": "peer-3", "name": "Peer 3", "host": "100.x.x.y", "port": 5051}]
}
```

## Validacao

```bash
flutter analyze
flutter test
```
