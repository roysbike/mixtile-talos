# Generic overlay для Mixtile Blade 3

[English version](README.md)

Talos Linux для отдельной Mixtile Blade 3 (RK3588), без Cluster Box:
обычный Talos с официальным ядром, без system extensions, PCIe 3.0 x4
краевого разъёма U.2 работает как обычный PCIe host. Каталог устроен как
плата в [siderolabs/sbc-rockchip](https://github.com/siderolabs/sbc-rockchip),
чтобы его можно было предложить туда как overlay `mixtile-blade3`.

Образ для Cluster Box (остальная часть репозитория) — другой overlay: там
тот же разъём работает как PCIe endpoint за коммутатором ASM2824, им
управляет openmiop.

| | Generic (`generic/`) | Cluster Box (`installers/blade3`, `artifacts/dtb/blade3`) |
| --- | --- | --- |
| PCIe3 x4 (fe150000) | host, 4 линии, `reset-gpios` GPIO4_B6 | endpoint (`openmiop,rk3588-pcie-ep`), 2 линии |
| PCIe3 x2 (fe160000) | выключен (PHY не разделён) | host для M.2 NVMe на backplane |
| PCIe SMMU (iommu@fc900000) | включён, как в mainline | выключен (у трафика endpoint нет владельца stream ID) |
| Extensions | нет | openmiop, drbd, zfs, iscsi-tools, panfrost, rockchip-rknn |
| Аргументы ядра | `console=ttyS2,1500000n8`, как у плат sbc-rockchip | ещё `ttyFIQ0`, `-module.sig_enforce` |
| U-Boot | общий: `artifacts/blade3/u-boot` (mainline U-Boot 2026.07 с файлами платы) | тот же |

Device tree `dtb/rk3588-mixtile-blade3.dts` — тот же файл, из которого
собирается U-Boot (`artifacts/blade3/u-boot/`): порт в стиле mainline от
Joshua Riek и Ricardo Pardini (Armbian). FUSB302 на входе питания USB-C в
Linux помечен `status = "fail"` (как на Rock 5B): повторное согласование
Power Delivery из Linux перезагрузило бы плату.

## Сборка

```bash
VARIANT=generic USERNAME=<registry namespace> ./build.sh all
VARIANT=generic ./scripts/verify-installer.sh _out
```

В `_out/`: `metal-arm64.raw.xz`, `installer-arm64.tar`,
`rk3588-mixtile-blade3.dtb`, `u-boot-rockchip.bin`, `BUILD-INFO.txt`
(`variant: generic`), `SHA256SUMS`. CI собирает его рядом с образом для
Cluster Box на каждый push в `claude/**`, `feat/**` и на теги (artifact
`mixtile-blade3-talos-generic-<tag>`).

## Проверка на Blade 3

Только на Blade 3 вне Cluster Box: в коробке линии PCIe3 x4 идут на
downstream-порт коммутатора ASM2824, и blade в роли второго root complex
там не проверялась.

1. Записать `metal-arm64.raw.xz` на microSD (`xz -dc … | dd of=/dev/sdX bs=4M conv=fsync`).
   U-Boot сначала пробует microSD, потом NVMe, потом eMMC.
2. Консоль: UART2 на 1500000 бод (отладочный разъём). Питание: 12 В на
   разъёме U.2 или блок USB-C PD, который умеет 12 В (их согласует U-Boot,
   Linux этот FUSB302 не трогает).
3. Проверить и потом записать результат в pull request:
   - загрузка с microSD; `talosctl apply-config` с установкой на eMMC,
     затем загрузка с eMMC;
   - оба порта RTL8125 2.5 GbE (PCIe 2.0 за ASM1182e) поднимают линк;
   - PCIe-устройство на разъёме U.2 (плата-переходник U.2) видно как
     PCIe 3.0 x4 (`talosctl read /proc/bus/pci/devices` или debug pod);
   - eMMC, microSD, USB, HDMI (если нужен), перезагрузка и `talosctl upgrade`;
   - в `talosctl dmesg | grep -iE 'error|fail'` ничего нового.

## Как предложить в siderolabs/sbc-rockchip

Файлы переносятся так; у имён стадий пропадает суффикс `-generic` (здесь
он нужен только чтобы не пересекаться со стадиями Cluster Box):

| Здесь | sbc-rockchip | Имя стадии там |
| --- | --- | --- |
| `generic/installer/` | `installers/mixtile-blade3/` | `mixtile-blade3` |
| `generic/dtb/` | `artifacts/dtb/mixtile-blade3/` | `dtb-mixtile-blade3` |
| `artifacts/blade3/u-boot/` | `artifacts/mixtile-blade3/u-boot/` | `u-boot-mixtile-blade3` |
| `generic/profiles/mixtile-blade3/` | `profiles/mixtile-blade3/` | (общая стадия `profiles`) |
| `generic/pkg.yaml` | записи в `installers/pkg.yaml` | (общая стадия `sbc-rockchip`) |
| — | строки в `README.md` и `MAINTAINERS.md` | |

Общие стадии `arm-trusted-firmware-rk3588` и `rkbin-rk3588` там есть под
теми же именами. Перед pull request прочитай их правила и AI policy
Siderolabs: всё, что ты отправляешь (код, сообщения коммитов, описание,
ответы на ревью), должно быть твоим, проверенным тобой на плате и
написанным твоими словами.
