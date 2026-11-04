# archr-bios-livres

Só BIOS livres, cada uma com a licença ao lado. Nenhuma imagem de fabricante
(Sony, Sega, Nintendo, SNK, NEC, Panasonic) entra aqui nem é baixada pelo
ArchR. O pacote não está na imagem: Configurações › Jogos › BIOS o instala
pelo pacman quando o usuário pede, e `archr-bios-livres install <sistema>`
copia o arquivo para `roms/bios/` só onde não há nada.

| Arquivo | Sistema e emulador | Projeto | Licença | Origem |
|---|---|---|---|---|
| `openbios.bin` | PlayStation, DuckStation | OpenBIOS do PCSX-Redux | MIT (fontes kanji Shinonome/efont e `xprintf` em domínio público) | compilado do código: `build-openbios.sh` |
| `cbios/cbios_main_msx1.rom`, `cbios_main_msx2.rom`, `cbios_main_msx2+.rom`, `cbios_sub.rom` | MSX, MSX2 e MSX2+, fMSX | C-BIOS 0.29a | BSD-2-Clause | release oficial `cbios-0.29a.zip` (SourceForge) |

## OpenBIOS

O PCSX-Redux não publica `openbios.bin` pronto. O arquivo vem do código
oficial, no espelho `pcsx-redux/nugget` (o submódulo `src/mips` do
PCSX-Redux) no commit `db68789861e1205bbd677bb4af5dca19c84433d1`, compilado
na imagem de build do próprio projeto (`ghcr.io/grumpycoders/pcsx-redux-build`).
Duas compilações limpas dão os mesmos bytes; o `package.mk` confere o
SHA-256 (`bc36eb48…31c9`, MD5 `f382ae14c65fa54960f0a73be313abaf`). Para
refazer: `bash build-openbios.sh`.

O DuckStation procura qualquer imagem de 512 KiB em `roms/bios` e prefere
uma BIOS conhecida a uma desconhecida: com a BIOS do console presente, ela
vale no lugar da OpenBIOS. Limites: alguns jogos param na abertura e não há
tela do cartão de memória. O pcsx_rearmed não precisa dela (tem HLE própria).

## C-BIOS

Roda cartuchos; não tem BASIC nem disco. O fMSX lê `MSX.ROM`, `MSX2.ROM` +
`MSX2EXT.ROM` e `MSX2P.ROM` + `MSX2PEXT.ROM`; o instalador copia a C-BIOS com
esses nomes só quando o arquivo não existe, então a BIOS do console, se o
usuário a copiar depois, substitui a livre. O blueMSX desta imagem procura
máquinas em `Machines/` e não escolhe a C-BIOS sozinho: a tela orienta usar o
fMSX.

## Fora do pacote

Sistemas com BIOS livre já embutida no núcleo não precisam de arquivo:
pcsx_rearmed (PlayStation), gpSP (`open_gba_bios`, GBA), melonDS (FreeBIOS,
DS), DraStic (HLE), Flycast (reios, Dreamcast), Yaba Sanshiro (BIOS emulada,
Saturn), atari800 (AltirraOS), PokeMini (FreeBIOS). Sega CD, PC Engine CD,
Neo Geo, 3DO, FDS, Lynx, Intellivision, Odyssey² e ColecoVision não têm
substituta livre madura: só a BIOS do console.
