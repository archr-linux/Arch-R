extlinux.conf tells U-Boot which kernel, device tree and command line to boot.

On the RK3562 handhelds (AISLPC RG43V PRO, RG52 MINI) the factory U-Boot on
the internal eMMC reads this file from the SD card. There is no boot.scr and
no device tree overlay: each screen has its own device tree.

  extlinux.conf                     RG43V PRO, 1024x768 (default)
  extlinux.conf.rg43v-pro           RG43V PRO, 1024x768
  extlinux.conf.rg43v-pro-1024x600  RG43V PRO, 1024x600 (screen not supported yet)
  extlinux.conf.rg52-mini           RG52 MINI, 720x1280

To switch, copy the matching file over extlinux.conf.
U-Boot's parser is strict: nothing may follow the .dtb path on the FDT line.
