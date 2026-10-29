# Built-in gamepad definitions (single source of truth)

Every built-in platform pad must exist in THREE shipped artifacts:

1. `packages/archr/config/emulationstation/es_input.cfg` (EmulationStation format, read by `mkcontroller`, the game controller functions and PortMaster)
2. `packages/emulators/libretro/retroarch/retroarch-joypads/gamepads/<name>.cfg` (RetroArch)
3. `packages/apps/gamecontrollerdb/config/gamecontrollerdb.txt` (SDL games and ports)

Historically these were maintained by hand and nothing checked they agreed:
the Soysauce pad shipped without the SDL entry, so ports saw no controller.
The JSON files in `defs/` are now the source of truth and `gen-input-configs`
keeps the three artifacts honest.

## Daily use

`make docker-*` refuses to build if the artifacts drifted from `defs/`:

    ./gen-input-configs verify          # what CI/build runs
    ./gen-input-configs write           # regenerate artifacts from defs

Only external controllers (USB/Bluetooth pads inherited from upstream
databases) stay unmanaged; the managed set is exactly the defs directory.

## Adding a new pad (example: a future R36T Max)

1. On the device, read the identity:

       cat /proc/bus/input/devices   # Name=, Vendor=, Product=, Version=

2. Compute the GUID the runtime will use (bus 0x19 for platform drivers):

       ./gen-input-configs guid "r36tmax_Gamepad" --vendor 1 --product 0x1199 --version 0x0100

   Vendor or product zero switches SDL to the name-embedded GUID form
   automatically, exactly like the runtime does (that mismatch was the
   Soysauce bug).

3. Copy the closest def (`defs/r36s_Gamepad.json`), adjust name, identity,
   buses, the SDL mapping string, the ES inputs and the RetroArch keys.

4. Materialize and check:

       ./gen-input-configs write "r36tmax_Gamepad"
       ./gen-input-configs verify

5. Commit the def together with the regenerated artifacts.

## Fidelity rules (deliberate)

* gamecontrollerdb line: byte-exact; the GUID is always recomputed from the
  identity fields (use `guid_override` only for entries that predate the
  tool and cannot be reproduced; none of the platform pads needs it).
* RetroArch cfg and es_input block: semantically exact (key/value sets);
  comments, blank lines and ordering are not preserved by `write`.
* `sdl_mapping` may be a per-GUID dict when buses legitimately differ
  (retrogame_joypad ships guide:b10 only on the 0x19 bus line).
