# Arch R Flasher

> Gravador de SD card + gerenciador de overlays para Arch R.

## Conceito

App desktop cross-platform (Windows, Linux, macOS) com duas funcoes:

1. **Flash** — Grava a imagem no SD card e aplica o overlay do painel selecionado
2. **Overlay** — Altera o painel de um SD card ja gravado (sem re-flash)

O usuario nao precisa saber nada de terminal, DTBs ou overlays.
Inspirado no Raspberry Pi Imager (flash) + ROCKNIX overlay_server (painel).

## Stack

**Tauri 2** (Rust backend + web frontend)

| Camada | Tecnologia | Motivo |
|--------|-----------|--------|
| Backend | Rust (Tauri) | Acesso raw a disco, download, manipulacao FAT32. Binario ~5MB (vs ~150MB Electron) |
| Frontend | HTML/CSS/JS (vanilla ou Svelte) | UI leve, sem framework pesado |
| Disk write | Rust (`std::fs::File` + raw device) | Gravacao direta no block device |
| FAT32 | Rust (`fatfs` crate) | Leitura/escrita na particao BOOT sem montar no OS |
| Download | Rust (`reqwest`) | Busca ultima release no GitHub |
| Empacotamento | Tauri bundler | .msi (Windows), .dmg (macOS), .AppImage/.deb (Linux) |

### Por que Tauri e nao Electron?

- Binario ~5MB vs ~150MB
- Sem Node.js runtime
- Rust da acesso direto a disco sem wrappers
- Alinhado com o lema: leve como uma pluma

## Arquitetura: Overlays (nao DTBs)

A imagem universal (`ArchR-R36S-no-panel`) contem:

- `/KERNEL` — kernel Image
- `/dtbs/` — 13 board DTBs (selecionados por boot.ini via hwrev/ADC)
- `/overlays/` — todos os 20 panel DTBOs disponiveis
- `/boot.ini` — carrega board DTB + aplica `overlays/mipi-panel.dtbo`

O **board DTB** (hardware: GPIOs, PMIC, joypad, audio) e selecionado automaticamente.
O **panel overlay** (init sequences do display) e o que o Flasher configura.

### Como funciona

1. Boot.ini seleciona o board DTB correto (hwrev ADC)
2. Boot.ini tenta carregar `overlays/mipi-panel.dtbo`
3. Se existir, aplica no DTB via `fdt apply` → display funciona
4. Se nao existir, boot continua sem overlay → display pode nao funcionar

O Flasher copia o DTBO do painel selecionado como `overlays/mipi-panel.dtbo`.

---

## Abas da Interface

### Aba 1: Flash (gravar imagem + painel)

```
┌─────────────────────────────────────────────────┐
│           ARCH R FLASHER                        │
│  ┌──────────┐ ┌──────────┐                      │
│  │  Flash   │ │ Overlay  │                      │
│  └──────────┘ └──────────┘                      │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │  Imagem: ArchR-R36S-no-panel             │  │
│  │  v1.0 beta2 (2026-03-04)                │  │
│  │  [Baixar nova versao] [Selecionar local] │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  1. Console:                                    │
│     ┌──────────────┐ ┌──────────────┐           │
│     │ R36S Original│ │  R36S Clone  │           │
│     └──────────────┘ └──────────────┘           │
│                                                 │
│  2. Painel:                                     │
│     ┌───────────────────────────────────────┐   │
│     │ ▼ Panel 4 (padrao, ~60%)              │   │
│     │   Panel 0                             │   │
│     │   Panel 1                             │   │
│     │   Panel 2                             │   │
│     │   Panel 3                             │   │
│     │   Panel 4 ★                           │   │
│     │   Panel 4-V22                         │   │
│     │   Panel 5                             │   │
│     │   R46H (1024x768)                     │   │
│     └───────────────────────────────────────┘   │
│                                                 │
│  3. Destino:                                    │
│     ┌───────────────────────────────────────┐   │
│     │ ▼ /dev/sdc (32GB SD Card)             │   │
│     └───────────────────────────────────────┘   │
│     [Atualizar lista]                           │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │           ★  GRAVAR  ★                   │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ████████████████░░░░░░░░ 67%  2.1GB/3.1GB      │
│  Gravando imagem...                             │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Aba 2: Overlay (trocar painel sem re-flash)

```
┌─────────────────────────────────────────────────┐
│           ARCH R FLASHER                        │
│  ┌──────────┐ ┌──────────┐                      │
│  │  Flash   │ │ Overlay  │                      │
│  └──────────┘ └──────────┘                      │
│                                                 │
│  SD Card com Arch R:                            │
│     ┌───────────────────────────────────────┐   │
│     │ ▼ /dev/sdc (32GB SD Card)             │   │
│     └───────────────────────────────────────┘   │
│     [Atualizar lista]                           │
│                                                 │
│  Overlay atual: panel4.dtbo                     │
│  Console detectado: original                    │
│                                                 │
│  Novo painel:                                   │
│     ┌───────────────────────────────────────┐   │
│     │ ▼ Panel 3                             │   │
│     └───────────────────────────────────────┘   │
│                                                 │
│  Ajustes (opcional):                            │
│     ┌─────────────────────────────────────┐     │
│     │  Rotacao:  [0°] [90°] [180°] [270°] │     │
│     │                                     │     │
│     │  Inversao de stick:                 │     │
│     │    [ ] Esquerdo   [ ] Direito       │     │
│     │                                     │     │
│     │  Audio:                             │     │
│     │    (•) Auto  ( ) Amplificado        │     │
│     │    ( ) Simples                      │     │
│     │                                     │     │
│     │  Inversao HP: [ ]                   │     │
│     └─────────────────────────────────────┘     │
│                                                 │
│  ┌───────────────────────────────────────────┐  │
│  │          ★  APLICAR OVERLAY  ★           │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ✓ Overlay aplicado! Insira o SD e reinicie.    │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## Paineis por Console

Cada painel tem seu proprio DTBO com init sequences nativas.
O Flasher copia o DTBO selecionado como `overlays/mipi-panel.dtbo`.

### R36S Original (8 paineis)

| Nome | DTBO | Padrao |
|------|------|--------|
| Panel 0 | panel0.dtbo | |
| Panel 1 | panel1.dtbo | |
| Panel 2 | panel2.dtbo | |
| Panel 3 | panel3.dtbo | |
| Panel 4 | panel4.dtbo | ★ padrao |
| Panel 4-V22 | panel4-v22.dtbo | |
| Panel 5 | panel5.dtbo | |
| R46H (1024x768) | r46h.dtbo | |

### R36S Clone (12 paineis)

| Nome | DTBO | Padrao |
|------|------|--------|
| Clone 1 (ST7703) | clone_panel_1.dtbo | |
| Clone 2 (ST7703) | clone_panel_2.dtbo | |
| Clone 3 (NV3051D) | clone_panel_3.dtbo | |
| Clone 4 (NV3051D) | clone_panel_4.dtbo | |
| Clone 5 (ST7703) | clone_panel_5.dtbo | |
| Clone 6 (NV3051D) | clone_panel_6.dtbo | |
| Clone 7 (JD9365DA) | clone_panel_7.dtbo | |
| Clone 8 G80CA (ST7703) | clone_panel_8.dtbo | ★ padrao |
| Clone 9 (NV3051D) | clone_panel_9.dtbo | |
| Clone 10 (ST7703) | clone_panel_10.dtbo | |
| R36 Max (ST7703 720x720) | r36_max.dtbo | |
| RX6S (NV3051D) | rx6s.dtbo | |

---

## Fluxo: Aba Flash

### Passo a passo

1. **App inicia** e busca a ultima release `ArchR-R36S-no-panel-*.img.xz` no GitHub Releases
2. **Imagem local ou download**: se ja tem uma imagem local, usa ela. Senao, oferece download
3. **Selecionar console**: R36S Original ou R36S Clone (dois botoes grandes)
4. **Selecionar painel**: dropdown muda conforme o console selecionado
5. **Selecionar destino**: lista de discos removiveis (SD cards)
6. **Gravar**: confirmacao ("Todos os dados do SD serao apagados"), barra de progresso
7. **Pos-gravacao**: injeta overlay + variant no BOOT (FAT32)
8. **Concluido**: "SD card pronto! Insira no R36S e ligue."

### Etapa 1: Gravar imagem raw

```
imagem.img.xz  →  descompacta on-the-fly  →  dd no block device
```

- Descompressao streaming (xz -> raw -> disco) para nao precisar de espaco extra
- Gravacao em blocos de 4MB (`bs=4M`)
- Barra de progresso baseada no tamanho descomprimido

### Etapa 2: Pos-gravacao (injetar configuracao)

Apos gravar a imagem raw, a particao BOOT (FAT32, particao 1) ja existe no SD. O Flasher:

1. **Abre a particao FAT32** diretamente no block device (sem montar no OS)
   - Usa crate `fatfs` em Rust para ler/escrever FAT32 via offset no disco
   - Offset da particao 1: lido da tabela de particoes (GPT ou MBR)

2. **Copia o DTBO do painel selecionado como `overlays/mipi-panel.dtbo`**:
   - Le o DTBO da pasta `overlays/` que ja esta na imagem (ex: `overlays/panel3.dtbo`)
   - Copia como `overlays/mipi-panel.dtbo`
   - Boot.ini vai aplicar esse overlay no proximo boot

3. **Escreve `panel-confirmed`**: conteudo "confirmed\n" (wizard nao roda)

4. **Escreve `variant`**: "original\n" ou "clone\n"
   - Arquivo na particao BOOT (FAT32)
   - Systemd service no primeiro boot copia para `/etc/archr/variant`

5. **Sync e fecha** (fsync obrigatorio em FAT32!)

### Diagrama

```
SD Card (pos-gravacao):

Offset 0          32KB           128MB                    ~3.2GB
├─── U-Boot ──────┤── BOOT (FAT32) ──┤──── STORAGE (ext4) ───┤
                  │                   │
                  ├── KERNEL          │
                  ├── boot.ini        │
                  ├── dtbs/           │  13 board DTBs (auto-select)
                  │   ├── rk3326-gameconsole-r36s.dtb
                  │   ├── rk3326-gameconsole-r36max.dtb
                  │   └── ... (13 total)
                  ├── overlays/       │
                  │   ├── mipi-panel.dtbo  ◄── escrito pelo Flasher
                  │   ├── panel0.dtbo
                  │   ├── panel4.dtbo
                  │   ├── clone_panel_8.dtbo
                  │   └── ... (20 total)
                  ├── panel-confirmed ◄── escrito pelo Flasher
                  └── variant         ◄── escrito pelo Flasher
```

---

## Fluxo: Aba Overlay

Permite trocar o painel de um SD card Arch R **sem re-gravar a imagem**.
Util quando o usuario troca de aparelho ou recebe um com painel diferente.

### Passo a passo

1. **Inserir SD card** com Arch R ja gravado
2. **Selecionar SD**: app detecta que tem Arch R (verifica presenca de `KERNEL` e `dtbs/`)
3. **Detectar estado atual**: le `overlays/mipi-panel.dtbo` e compara com os DTBOs conhecidos
4. **Selecionar novo painel**: dropdown (mesmo que na aba Flash)
5. **Ajustes opcionais** (inspirado no ROCKNIX overlay_server):
   - Rotacao do display (0/90/180/270)
   - Inversao de sticks analogicos (esquerdo/direito)
   - Modo de audio (auto/amplificado/simples)
   - Inversao da deteccao de headphone
6. **Aplicar**: copia DTBO selecionado para `overlays/mipi-panel.dtbo` + fsync
7. **Concluido**: "Overlay aplicado!"

### Deteccao do overlay atual

Para mostrar qual painel esta ativo, o Flasher:

1. Le `overlays/mipi-panel.dtbo` do SD card
2. Calcula hash (MD5/SHA256)
3. Compara com hashes dos 20 DTBOs conhecidos (embutidos no app)
4. Se match: mostra nome do painel
5. Se nao match: "Overlay personalizado" (pode ter sido gerado pelo overlay_server)

### Ajustes de painel (inspirado ROCKNIX overlay_server)

O overlay_server do ROCKNIX gera overlays a partir de DTBs de estoque, suportando
modificacoes como rotacao, inversao de sticks, e audio routing. O Flasher integra
essas opcoes diretamente:

| Ajuste | Flags | Descricao |
|--------|-------|-----------|
| Rotacao | DR0, DR90, DR180, DR270 | Rotacao do display (0-270 graus) |
| Inversao stick esquerdo | LSi | Inverte eixos X/Y do stick esquerdo |
| Inversao stick direito | RSi | Inverte eixos RX/RY do stick direito |
| Audio amplificado | SRa | Usa amplificador externo (rk817-sound-amplified) |
| Audio simples | SRs | Roteamento direto SPK/HP (rk817-sound-simple) |
| Inversao HP detect | HPi | Inverte polaridade da deteccao de headphone |

Quando o usuario seleciona ajustes, o Flasher **modifica o DTBO em memoria** antes
de gravar no SD card:

1. Le o DTBO base do painel selecionado
2. Aplica as modificacoes (altera propriedades no FDT)
3. Grava o DTBO modificado como `overlays/mipi-panel.dtbo`

Isso e feito puramente em Rust usando a crate `fdt` para manipulacao binaria do DTB.

---

## Deteccao de Imagem

### Fonte: GitHub Releases

```
GET https://api.github.com/repos/archr-linux/Arch-R/releases/latest
```

Procura por asset com nome `ArchR-R36S-no-panel-*.img.xz`.

### Cache local

- Imagens baixadas ficam em:
  - Windows: `%APPDATA%\ArchR-Flasher\images\`
  - macOS: `~/Library/Application Support/ArchR-Flasher/images/`
  - Linux: `~/.local/share/archr-flasher/images/`
- Se ja tem a versao mais recente localmente, nao baixa de novo
- Botao "Selecionar arquivo local" para imagens baixadas manualmente

## Deteccao de Discos

### Linux
```rust
// Listar /sys/block/sd* e /sys/block/mmcblk*
// Filtrar por removable=1
// Ler size, vendor, model
```

### macOS
```rust
// diskutil list -plist
// Filtrar por removable=true, protocol=USB ou SD
```

### Windows
```rust
// WMI: Win32_DiskDrive WHERE MediaType='Removable Media'
// Ou: SetupDiGetClassDevs + DeviceIoControl
```

### Protecoes

- **Nunca listar discos fixos** (HDD/SSD do sistema)
- **Filtro de tamanho**: ignorar discos > 128GB (provavelmente nao e SD card do R36S)
- **Confirmacao com nome do disco**: "Gravar em SANDISK 32GB (/dev/sdc)? TODOS OS DADOS SERAO APAGADOS."
- **Bloquear disco do sistema**: nunca permitir gravar no disco onde o OS esta rodando

### Validacao de SD Arch R (aba Overlay)

Para a aba Overlay, o Flasher precisa verificar que o SD card ja tem Arch R:

1. Montar (ou ler via fatfs) a particao 1
2. Verificar presenca de: `KERNEL`, `dtbs/`, `overlays/`, `boot.ini`
3. Se presente: SD valido, mostrar overlay atual
4. Se ausente: "Este SD card nao contem Arch R"

## Permissoes de Disco

### Linux
- Precisa de root para gravar em block device
- Usar `pkexec` para elevar privilegios (sem terminal)
- Aba Overlay: tambem precisa de `pkexec` para escrever no SD

### macOS
- `diskutil unmountDisk /dev/diskN` antes de gravar
- Precisa de permissao de admin (Authorization Services)

### Windows
- Precisa de admin para abrir `\\.\PhysicalDriveN`
- UAC prompt automatico via manifesto do executavel

## Estrutura do Projeto

```
archr-flasher/
├── src-tauri/
│   ├── src/
│   │   ├── main.rs              # Entry point Tauri
│   │   ├── disk.rs              # Deteccao e listagem de discos
│   │   ├── flash.rs             # Gravacao raw + descompressao xz
│   │   ├── overlay.rs           # Leitura/escrita de overlays no SD
│   │   ├── fat32.rs             # Leitura/escrita FAT32 direta
│   │   ├── github.rs            # Download de releases
│   │   ├── panels.rs            # Definicao dos paineis + hashes DTBOs
│   │   └── dtb_modify.rs        # Modificacao binaria de DTBOs (rotacao, sticks, audio)
│   ├── Cargo.toml
│   └── tauri.conf.json
├── src/
│   ├── index.html               # UI principal (2 abas: Flash + Overlay)
│   ├── style.css                # Estilo (tema escuro, cores Arch R)
│   └── main.js                  # Logica de UI
├── assets/
│   ├── icon.png                 # Icone do app (logo Arch R)
│   └── i18n/                    # Traducoes
│       ├── en.json
│       └── pt-BR.json
└── README.md
```

## Dependencias Rust (Cargo.toml)

```toml
[dependencies]
tauri = { version = "2", features = ["shell-open"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
reqwest = { version = "0.12", features = ["json", "stream"] }
tokio = { version = "1", features = ["full"] }
xz2 = "0.1"                    # Descompressao .xz streaming
fatfs = "0.4"                   # Leitura/escrita FAT32 sem montar
gpt = "3"                       # Leitura de tabela de particoes GPT
byteorder = "1"                 # Leitura MBR
fdt = "0.1"                     # Manipulacao binaria de DTB/DTBO
md-5 = "0.10"                   # Hash para identificar overlay atual
```

## UI: Tema Visual

- **Fundo**: preto (#0a0a0a)
- **Destaque**: azul Arch (#1793D1)
- **Texto**: branco (#f0f0f0)
- **Botoes**: azul Arch com hover mais claro
- **Progresso**: barra azul gradiente
- **Logo**: "ARCH R" no topo (mesma fonte Quantico do splash)
- **Abas**: Flash e Overlay (tab bar no topo)
- **Ajustes**: secao colapsavel na aba Overlay (expandir para ver opcoes avancadas)

## Internacionalizacao (i18n)

O Flasher deve ser multilinguagem. O idioma e detectado automaticamente pelo OS, com fallback para ingles.

### Idiomas

| Codigo | Idioma | Status |
|--------|--------|--------|
| en | English | Base (fallback) |
| pt-BR | Portugues (Brasil) | Prioritario |
| es | Espanol | Futuro |
| zh | Chinese | Futuro |

### Implementacao

Arquivo JSON por idioma em `assets/i18n/`.

Exemplo `en.json`:
```json
{
  "title": "ARCH R FLASHER",
  "tab_flash": "Flash",
  "tab_overlay": "Overlay",
  "image": "Image",
  "no_image": "No image selected",
  "select_file": "Select file",
  "download_latest": "Download latest version",
  "console": "Console",
  "panel": "Panel",
  "select_panel": "Select panel",
  "destination": "Destination",
  "select_sd": "Select SD card",
  "no_sd": "No SD card found",
  "refresh": "Refresh list",
  "flash": "FLASH",
  "confirm_title": "Confirm flash",
  "confirm_text": "Flash Arch R to {disk}?",
  "confirm_warning": "ALL DATA ON THE SD CARD WILL BE ERASED!",
  "cancel": "Cancel",
  "writing": "Writing image...",
  "syncing": "Syncing...",
  "configuring": "Applying panel overlay...",
  "done": "SD card ready! Insert in R36S and power on.",
  "recommended": "recommended",
  "overlay_current": "Current overlay",
  "overlay_new": "New panel",
  "overlay_custom": "Custom overlay",
  "overlay_apply": "APPLY OVERLAY",
  "overlay_done": "Overlay applied! Insert SD and reboot.",
  "overlay_not_archr": "This SD card does not contain Arch R.",
  "adjustments": "Adjustments (optional)",
  "rotation": "Rotation",
  "stick_inversion": "Stick inversion",
  "stick_left": "Left",
  "stick_right": "Right",
  "audio_mode": "Audio mode",
  "audio_auto": "Auto",
  "audio_amplified": "Amplified",
  "audio_simple": "Simple",
  "hp_inversion": "Invert HP detection"
}
```

### Deteccao de idioma

1. Tauri detecta o locale do OS via `sys_locale` crate
2. Frontend recebe o locale via comando Tauri
3. Carrega o JSON correspondente (ou `en.json` como fallback)
4. Todas as strings da UI vem do arquivo de traducao

## Build e Release

### Compilacao

```bash
# Requisitos: Rust, Node.js (para Tauri CLI)
cargo install tauri-cli

# Dev
cargo tauri dev

# Build release (gera instalador por plataforma)
cargo tauri build
```

### CI/CD (GitHub Actions)

```yaml
# .github/workflows/flasher-release.yml
# Matrix: ubuntu-latest, macos-latest, windows-latest
# Cada um gera: .AppImage/.deb, .dmg, .msi
# Upload como assets na release do Flasher
```

### Distribuicao

| Plataforma | Formato | Tamanho estimado |
|-----------|---------|-----------------|
| Linux | .AppImage + .deb | ~8MB |
| macOS | .dmg | ~10MB |
| Windows | .msi | ~8MB |

## Primeiro Boot (pos-Flasher)

O SD gravado pelo Flasher ja tem tudo configurado:

1. Boot.ini seleciona board DTB correto via hwrev (automatico)
2. Boot.ini aplica `overlays/mipi-panel.dtbo` (painel selecionado pelo Flasher)
3. Display funciona desde o primeiro boot
4. `variant` na particao BOOT = "original" ou "clone"
5. `panel-confirmed` presente = wizard nao roda
6. Systemd service le `variant` do BOOT e copia para `/etc/archr/variant`
7. EmulationStation inicia normalmente

**Zero configuracao no device.** Liga e usa.

## Systemd: Variant Sync Service

Service no rootfs para copiar `variant` do BOOT:

```ini
# /etc/systemd/system/archr-variant-sync.service
[Unit]
Description=Sync variant from BOOT partition
After=local-fs.target
RequiresMountsFor=/boot
ConditionPathExists=!/etc/archr/variant

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'test -f /boot/variant && cp /boot/variant /etc/archr/variant'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Roda apenas uma vez (ConditionPathExists). Apos copiar, nao roda mais.

## Fases de Desenvolvimento

### Fase 1: Core funcional
- [ ] Projeto Tauri inicializado
- [ ] UI basica com 2 abas (Flash + Overlay)
- [ ] Selecao console + painel + disco
- [ ] Gravacao de imagem local (.img, sem .xz)
- [ ] Pos-gravacao: copiar DTBO + variant + panel-confirmed
- [ ] Aba Overlay: trocar overlay sem re-flash
- [ ] Testar em Linux

### Fase 2: Polish
- [ ] Descompressao .xz streaming
- [ ] Download automatico do GitHub Releases
- [ ] Cache de imagens
- [ ] Deteccao de overlay atual (hash comparison)
- [ ] Ajustes avancados (rotacao, sticks, audio)
- [ ] Deteccao de discos (Linux + macOS + Windows)
- [ ] Barra de progresso real

### Fase 3: Release
- [ ] CI/CD para 3 plataformas
- [ ] Icone e branding
- [ ] i18n (pt-BR + en)
- [ ] Testes em hardware real (Original + Clone)
- [ ] Publicar na pagina do projeto
