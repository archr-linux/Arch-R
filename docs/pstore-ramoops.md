# pstore/ramoops no RK3326

Settings › System › Diagnostics mostra "Falhas guardadas", lidas de
`/sys/fs/pstore`. O kernel do RK3326 já tem `CONFIG_PSTORE_RAM=y`, mas o
device tree do R36S (e dos outros RK3326) **não tem o nó `ramoops`**:
conferido em 2026-10-31 no aparelho (`/proc/device-tree/reserved-memory`
não existe, `/sys/module/pstore/parameters/backend` é `(null)`). Sem o nó,
a página mostra "Indisponível" e `archr-debug status` diz `PSTORE=none`.

## O overlay

`projects/ArchR/packages/kernel-drivers/device-tree-overlays/sources/RK3326/rk3326-ramoops.dts`
reserva 1 MiB em `0x30000000` para o ramoops (registro de 128 KiB, console
de 512 KiB, pmsg de 128 KiB). É o mesmo nó que já foi usado à mão para achar
o travamento do panfrost (patch 035). Aplicado com `fdtoverlay` sobre o
`rk3326-gameconsole-r36s.dtb` da imagem, o resultado tem o nó
`/reserved-memory/ramoops@30000000` e nada mais muda.

Depois de um travamento seguido de reinício, o boot seguinte traz
`console-ramoops-0` (o console do boot que caiu) e, quando o kernel chegou a
reiniciar sozinho, `dmesg-ramoops-N` (o oops). O relatório (`archr-report`)
copia esses arquivos para `pstore/`.

## Ainda não ligado

O pacote `device-tree-overlays` só entra na imagem com
`ArchR_DEVICE_TREE_OVERLAYS=yes`, que o RK3326 não define, e o `dtb_overlay`
não é instalado no RK3326. Para ligar:

1. `ArchR_DEVICE_TREE_OVERLAYS="yes"` em `projects/ArchR/devices/RK3326/options`
   (o `.dtbo` vai para `/usr/share/bootloader/overlays` e o `update.sh` do
   bootloader o copia para `/flash/overlays`);
2. acrescentar `/overlays/rk3326-ramoops.dtbo` à linha `FDTOVERLAYS` do
   `/flash/extlinux/extlinux.conf`, sem tirar o `mipi-panel.dtbo`;
3. reiniciar e conferir `cat /sys/module/pstore/parameters/backend` (deve
   dizer `ramoops`).

Riscos a medir antes de ligar por padrão: a faixa `0x30000000` precisa ficar
fora do que o U-Boot e o TPL usam em todas as placas RK3326 com 1 GB (e nas
de 512 MB ela não existe: lá o overlay deve ir para `0x1f000000`, ou ficar
desligado). Não foi trocado DTB em nenhum aparelho nesta frente.
