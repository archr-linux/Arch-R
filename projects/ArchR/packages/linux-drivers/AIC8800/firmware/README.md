# Firmware AIC8800DC, conjunto do fabricante

Origem: Tenda, pacote `wifi6-adapter-linux-driver` versão 1.0.1.10, diretório
`Appendix/linux_driver_sourcecode/aic8800_linux_drvier/fw/aic8800DC`.

Estes arquivos são sobrepostos ao firmware que vem embutido na árvore do driver
(AveyondFly `aic8800-usb`) durante o `makeinstall_target`. O driver continua
sendo o do AveyondFly; só o firmware passa a ser o do fabricante.

## Por quê

A árvore do AveyondFly carrega um build mais antigo do firmware. Dos 8 arquivos
que um 8800DC `u02` (`chip_id=7, chip_sub_id=1, chip_mcu_id=1`) realmente
carrega, 6 divergiam do release oficial:

| Arquivo                          | AveyondFly | Tenda 1.0.1.10 |
|----------------------------------|------------|----------------|
| `fmacfw_patch_8800dc_u02.bin`    | `ec8ee791` | `bfd8ea1d`     |
| `fmacfw_patch_tbl_8800dc_u02.bin`| `c0538d74` | `7b5fde60`     |
| `fmacfw_calib_8800dc_u02.bin`    | `061790c6` | `c82039f6`     |
| `fw_patch_8800dc_u02.bin`        | `c4c0e536` | `bcb6a35e`     |
| `fw_patch_table_8800dc_u02.bin`  | `c1060ddc` | `530ce149`     |
| `fw_patch_8800dc_u02_ext0.bin`   | `cfe837e7` | `7f88e5fd`     |

Só `fw_adid_8800dc_u02.bin` e `lmacfw_rf_8800dc.bin` já eram idênticos. Os
arquivos de texto (`aic_userconfig_*`, `aic_powerlimit_*`) também já batiam.

Usar o firmware do próprio fabricante junto do driver que o acompanha é o
arranjo certo por si só, e o conjunto oficial carrega sem problema neste
hardware: o `AICWFDBG` imprimiu `md5:bfd8ea1d...` e `md5:7b5fde60...` e o
`wlan0` subiu normalmente.

O que este alinhamento **não** faz é resolver o `device descriptor read,
error -71`. A primeira suposição registrada aqui era essa, e o boot de
2026-09-04 com o firmware oficial já instalado mostrou que ela é insustentável.
O log do console coloca os seis `-71` na reenumeração que segue o mode switch de
u-disk para WLAN, e o `aic_load_fw_usb` só se registra depois disso. Nenhum byte
de firmware chegou ao chip quando os erros acontecem, então o firmware não pode
tê-los causado. A causa está no dwc2 durante a reenumeração, não aqui.

O sistema se recupera sozinho: depois de cinco tentativas e um `unable to
enumerate USB device`, o controlador dwc2 é removido e reprobado, e aí o dongle
enumera limpo como `2604:0013`. Nesse mesmo boot não houve nenhum timeout de
LMAC, mas eles sempre foram intermitentes, então um boot não serve de prova.

## O que isto não resolve

Não muda a banda. O dongle Tenda AX300 (`2604:0013`) é Wi-Fi 6 de banda única,
2.4GHz, 286 Mbps. O firmware oficial também responde `is_5g_support = 0`.

## Ao atualizar

Substitua o diretório inteiro por uma cópia fiel do `fw/aic8800DC` do pacote
novo e anote aqui a versão. Não edite arquivos individualmente.
