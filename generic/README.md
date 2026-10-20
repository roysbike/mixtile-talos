# Generic Mixtile Blade 3 overlay

[Русская версия](README.ru.md)

Talos Linux for a Mixtile Blade 3 (RK3588) on its own, without the
Cluster Box: plain Talos with the official kernel, no system extensions,
the PCIe 3.0 x4 of the U.2 edge connector as a normal PCIe host. The
directory is laid out like a board in
[siderolabs/sbc-rockchip](https://github.com/siderolabs/sbc-rockchip), so
that it can be proposed there as the `mixtile-blade3` overlay.

The Cluster Box image (the rest of this repository) is a different
overlay: there the same connector is a PCIe endpoint behind the box's
ASM2824 switch, driven by openmiop.

| | Generic (`generic/`) | Cluster Box (`installers/blade3`, `artifacts/dtb/blade3`) |
| --- | --- | --- |
| PCIe3 x4 (fe150000) | host, 4 lanes, `reset-gpios` GPIO4_B6 | endpoint (`openmiop,rk3588-pcie-ep`), 2 lanes |
| PCIe3 x2 (fe160000) | disabled (the PHY is not split) | host for the M.2 NVMe on the backplane |
| PCIe SMMU (iommu@fc900000) | enabled, as in mainline | disabled (endpoint traffic has no stream ID owner) |
| Extensions | none | openmiop, drbd, zfs, iscsi-tools, panfrost, rockchip-rknn |
| Kernel arguments | `console=ttyS2,1500000n8`, as the sbc-rockchip boards | also `ttyFIQ0`, `-module.sig_enforce` |
| U-Boot | shared: `artifacts/blade3/u-boot` (mainline U-Boot 2026.07, board files added) | same |

The device tree `dtb/rk3588-mixtile-blade3.dts` is the same file U-Boot
is built with (`artifacts/blade3/u-boot/`): the mainline-style port by
Joshua Riek and Ricardo Pardini (Armbian). Its USB-C power-input FUSB302
is `status = "fail"` in Linux (the Rock 5B way): renegotiating power
delivery from Linux would reset the board.

## Build

```bash
VARIANT=generic USERNAME=<registry namespace> ./build.sh all
VARIANT=generic ./scripts/verify-installer.sh _out
```

Output in `_out/`: `metal-arm64.raw.xz`, `installer-arm64.tar`,
`rk3588-mixtile-blade3.dtb`, `u-boot-rockchip.bin`, `BUILD-INFO.txt`
(`variant: generic`), `SHA256SUMS`. CI builds it next to the Cluster Box
image on every push to `claude/**`, `feat/**` and tags (artifact
`mixtile-blade3-talos-generic-<tag>`).

## Test on a Blade 3

Only on a Blade 3 outside the Cluster Box: in the box the PCIe3 x4 lanes
go to a downstream port of the ASM2824 switch, and a blade acting as a
second root complex there is untested.

1. Write `metal-arm64.raw.xz` to a microSD card (`xz -dc … | dd of=/dev/sdX bs=4M conv=fsync`).
   U-Boot tries the microSD first, then NVMe, then the eMMC.
2. Serial console: UART2 at 1500000 baud (debug header). Power: 12 V on
   the U.2 connector, or a USB-C PD supply that offers 12 V (U-Boot
   negotiates it; Linux leaves that FUSB302 alone).
3. Check, and note the result in the pull request later:
   - boots from microSD; `talosctl apply-config` and install to the eMMC,
     then boots from the eMMC;
   - both RTL8125 2.5 GbE ports (PCIe 2.0 behind the ASM1182e) get a link;
   - a PCIe device on the U.2 connector (U.2 breakout board) shows up as
     PCIe 3.0 x4 (`talosctl read /proc/bus/pci/devices` or a debug pod);
   - eMMC, microSD, USB, HDMI (if used), reboot and `talosctl upgrade`;
   - `talosctl dmesg | grep -iE 'error|fail'` has nothing new.

## Proposing it to siderolabs/sbc-rockchip

Files map to sbc-rockchip as follows; stage names lose the `-generic`
suffix (it only avoids clashes with the Cluster Box stages here):

| Here | sbc-rockchip | Stage name there |
| --- | --- | --- |
| `generic/installer/` | `installers/mixtile-blade3/` | `mixtile-blade3` |
| `generic/dtb/` | `artifacts/dtb/mixtile-blade3/` | `dtb-mixtile-blade3` |
| `artifacts/blade3/u-boot/` | `artifacts/mixtile-blade3/u-boot/` | `u-boot-mixtile-blade3` |
| `generic/profiles/mixtile-blade3/` | `profiles/mixtile-blade3/` | (shared `profiles` stage) |
| `generic/pkg.yaml` | entries in `installers/pkg.yaml` | (shared `sbc-rockchip` stage) |
| — | rows in `README.md` and `MAINTAINERS.md` | |

The shared stages `arm-trusted-firmware-rk3588` and `rkbin-rk3588` exist
there under the same names. Read their contribution rules and the
Siderolabs AI policy before opening the pull request: everything you
submit (code, commit messages, the description, replies to review) has
to be yours, tested by you on the board, and written in your own words.
