# Talos Linux для Mixtile Blade 3 в Cluster Box

[English](README.md) · [Русский](README.ru.md)

**Образы Talos Linux (Kubernetes) для Mixtile Blade 3 (RK3588) в Mixtile
Cluster Box со встроенной сетью PCIe-фабрики `omi0`.** Репозиторий
собирает overlay платы для Talos ARM64 (U-Boot, device tree, установщик),
system extension `openmiop` и готовые образы диска и установщика. На
блейдах ничего собирать не нужно.

**Текущий релиз: [v0.6.1](https://github.com/roysbike/mixtile-talos/releases/tag/v0.6.1)**
(2026-10-21): Talos v1.14.4, Linux 6.18.57-talos, входит в OpenMIOP Stack
v0.6.1. Release notes: [v0.6.1](docs/release-notes/v0.6.1.md) ·
[CHANGELOG.md](CHANGELOG.md).

```
ghcr.io/roysbike/mixtile-talos-installer@sha256:c0fe6ec4eb157ab8d993477b7b85abc982dc1ecbd7a9fb3cc0bcb054159fda8e
```

## Содержание

* [OpenMIOP Stack](#openmiop-stack)
* [Возможности](#возможности)
* [Оборудование и требования](#оборудование-и-требования)
* [Что в образе](#что-в-образе)
* [Установка нового узла](#установка-нового-узла)
* [Конфигурация машины для omi0](#конфигурация-машины-для-omi0)
* [Обновление узла](#обновление-узла)
* [Проверка](#проверка)
* [Технические подробности](#технические-подробности)
* [Известные ограничения](#известные-ограничения)
* [Сборка](#сборка)
* [Структура репозитория](#структура-репозитория)

## OpenMIOP Stack

Mixtile поставляет Cluster Box со своей прошивкой BMC и своим сетевым
драйвером для блейдов (MIOP). **OpenMIOP Stack** — независимая открытая
замена из трёх репозиториев, которые выпускаются вместе:

| Репозиторий | Что даёт | Stack v0.6.1 |
| --- | --- | --- |
| [pcie-ep-net](https://github.com/roysbike/pcie-ep-net) | драйвер блейда `openmiop-ep` (`omi0`), модуль BMC `omi-rc`, модули платы Blade 3 | [v0.6.1](https://github.com/roysbike/pcie-ep-net/releases/tag/v0.6.1) |
| **mixtile-talos** (этот) | Talos Linux (Kubernetes) для Blade 3 со встроенным openmiop | [v0.6.1](https://github.com/roysbike/mixtile-talos/releases/tag/v0.6.1) (Talos v1.14.4) |
| [mixtile-clusterbox-mt7620a-openwrt](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt) | OpenWrt для BMC: питание и консоли блейдов, сторона BMC в openmiop, сетевой край кластера, веб-интерфейс, обновления | [v0.4.0](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt/releases/tag/v0.4.0) (OpenWrt 25.12.6) |

```
        BMC Cluster Box (MT7620A, OpenWrt)  omi-rc, omi0 10.20.0.1, шлюз в LAN
                       |  PCIe Gen1 x1
                 PCIe-коммутатор ASM2824    трафик блейд-блейд остаётся здесь
              /      /        \       \     по Gen3 x2
         слот 1   слот 2   слот 3   слот 4  Mixtile Blade 3: Talos + openmiop, omi0 10.20.0.x
```

## Возможности

* **Официальный Talos и официальное ядро.** Talos v1.14.4 с ядром
  Siderolabs 6.18.57-talos и официальными расширениями под него (DRBD,
  ZFS, iSCSI, GPU Panfrost, NPU Rockchip).
* **Поддержка платы Blade 3.** Device tree и U-Boot 2026.07 для Blade 3
  (из mainline-порта Armbian), TF-A и DDR-блоб Rockchip, U-Boot в секторе
  64, последовательная консоль на UART2.
* **Сеть PCIe-фабрики.** Расширение `openmiop` даёт `omi0`:
  7,8-8,0 Гбит/с на поток между блейдами, BMC — шлюз в LAN.
* **NVMe на полной скорости в шасси.** M.2 NVMe поднимается в Gen3 x2, а
  `blade3-nvme-recover` возвращает его после сброса PCIe в Cluster Box
  (перезагрузка BMC).
* **Индикаторы портов.** `blade3-leds` управляет индикаторами портов
  Ethernet 2.5G.
* **Воспроизводимые релизы.** GitHub Actions собирает каждый релиз на
  нативном arm64, закрепляет расширения по digest, проверяет установщик
  (`scripts/verify-installer.sh`) и публикует образ, загрузочные файлы и
  контрольные суммы.

## Оборудование и требования

| | |
| --- | --- |
| Плата | Mixtile Blade 3 (RK3588, 4× Cortex-A76 + 4× Cortex-A55), установка на eMMC |
| Шасси | Mixtile Cluster Box (PCIe-коммутатор ASM2824, BMC MT7620A), до 4 блейдов |
| Прошивка BMC | [прошивка ClusterBox v0.4.0](https://github.com/roysbike/mixtile-clusterbox-mt7620a-openwrt/releases/tag/v0.4.0) (или v0.3.0) для `omi0`. Со штатной прошивкой Mixtile блейды загружаются и работают, но без `omi0` |
| Kubernetes | образ версию не фиксирует; проверено с v1.34.3 (Cozystack) |
| Проверено на | Cluster Box с четырьмя Blade 3: 3 control plane + 1 worker, DRBD/LINSTOR, ZFS, CloudNativePG |

Образ собран для блейдов в Cluster Box: device tree настраивает
PCIe-контроллер как endpoint в сторону шасси. Отдельный Blade 3 — не
проверенная конфигурация.

## Что в образе

| Компонент | Версия / источник |
| --- | --- |
| Talos, imager | v1.14.4 |
| Ядро | 6.18.57-talos (официальное ядро Talos; пакеты Talos `v1.14.0-44-g2ec10eb`) |
| U-Boot | v2026.07, конфигурация Blade 3 из mainline-порта Armbian |
| TF-A | `lts-v2.14.6` |
| DDR-блоб | rkbin `74213af1` |
| Device tree | `rk3588-mixtile-blade3.dtb` (порт Armbian + изменения PCIe для Cluster Box, см. [Технические подробности](#технические-подробности)) |
| Расширение openmiop | `0.6.1-v1.14.4`: `openmiop-ep`, `blade3-nvme-recover`, `blade3-leds` из [pcie-ep-net v0.6.1](https://github.com/roysbike/pcie-ep-net/releases/tag/v0.6.1) |
| Официальные расширения | `drbd 9.3.4`, `zfs 2.4.4`, `iscsi-tools v0.2.0`, `panfrost`, `rockchip-rknn` (сборки под v1.14.4, закреплены по digest) |
| Аргументы ядра | `console=tty0 console=ttyS2,1500000n8 cma=128MB … -module.sig_enforce sysctl.net.core.default_qdisc=fq` |

Файлы релиза:

| Файл | Для чего |
| --- | --- |
| установщик `ghcr.io/roysbike/mixtile-talos-installer@sha256:…` | `talosctl upgrade` и `machine.install.image` |
| `openmiop-0.6.1-blade3-talos-1.14.4-arm64.raw.xz` | образ диска для нового узла (eMMC) |
| `openmiop-0.6.1-blade3-talos-1.14.4-arm64-boot-files.tar.gz` | DTB, `u-boot-rockchip.bin`, `openmiop-ep.ko`, манифест расширения |
| `SHA256SUMS`, `BUILD-INFO.txt` | контрольные суммы, запись о сборке (коммит, версии, digest'ы) |

## Установка нового узла

Каждый блейд прошивается отдельно, по USB в режиме MaskROM.

1. Скачайте из релиза образ диска и `SHA256SUMS` и проверьте их:
   `sha256sum -c --ignore-missing SHA256SUMS` (macOS: `shasum -a 256 -c`).
2. Установите `rkdeveloptool` (Linux: пакет дистрибутива или
   [rockchip-linux/rkdeveloptool](https://github.com/rockchip-linux/rkdeveloptool);
   macOS: `brew tap IgorKha/rkdeveloptool && brew install rkdeveloptool`)
   и возьмите SPL-загрузчик Blade 3 `rk3588_spl_loader_v1.08.111.bin` из
   [инструкции Mixtile](https://www.mixtile.com/docs/installing-talos-on-mixtile-blade-3/).
   Другой загрузчик RK3588 не подставляйте; он нужен только для доступа
   к eMMC по USB.
3. Переведите DIP-переключатель 4 блейда в ON, передёрните питание и
   проверьте, что плата видна: `rkdeveloptool ld`.
4. Запишите образ:

   ```sh
   ./scripts/flash-blade3-macos.sh --image openmiop-0.6.1-blade3-talos-1.14.4-arm64.raw.xz \
       --loader rk3588_spl_loader_v1.08.111.bin
   ```

   Скрипт (написан для macOS; нужны только `rkdeveloptool` и `xz`)
   проверяет образ и подпись U-Boot в нём, ждёт ровно один Blade 3 в
   MaskROM, спрашивает подтверждение и пишет eMMC. Вручную:
   `rkdeveloptool db <loader>`, затем `rkdeveloptool wl 0 <image.raw>`,
   `rkdeveloptool rd`.
5. Верните DIP-переключатель 4 и загрузитесь. Последовательная консоль
   (UART2, 1 500 000 бод; в Cluster Box — CONSOLE в веб-интерфейсе BMC)
   должна показать `enabling system extension openmiop 0.6.1-v1.14.4`.
6. Примените конфигурацию машины с `machine.install.disk: /dev/mmcblk0`,
   `machine.install.image` = установщик выше и
   [документами для omi0](#конфигурация-машины-для-omi0).

Применение конфигурации к узлу, загруженному со старого образа, его не
переустанавливает (`install sequence: 0 phase(s)`): после этого выполните
на нём `talosctl upgrade --image …`. Новый control-plane узел не
войдёт в etcd, пока в кластере числится мёртвый участник: сначала удалите
его (`talosctl etcd remove-member <id>`, после `etcd snapshot`).

## Конфигурация машины для omi0

Свой адрес на каждый блейд (10.20.0.1 — это BMC). Применяется без
перезагрузки: `talosctl -n <node> patch mc --mode no-reboot -p @omi.yaml`.

```yaml
# omi.yaml
machine:
  kernel:
    modules:
      - name: openmiop_ep
---
apiVersion: v1alpha1
kind: LinkAliasConfig
name: omi0
selector:
  match: link.driver == "openmiop-ep"
---
apiVersion: v1alpha1
kind: LinkConfig
name: omi0
up: true
mtu: 9000
addresses:
  - address: 10.20.0.<N>/24
```

Без `LinkAliasConfig` Talos называет интерфейс `enx<mac>`. Параметры
драйвера (очереди, CPU, offload) задаются в
`machine.kernel.modules[].parameters`; см.
[README pcie-ep-net](https://github.com/roysbike/pcie-ep-net/blob/main/README.ru.md#настройка).

## Обновление узла

```sh
talosctl -n <node> upgrade --image ghcr.io/roysbike/mixtile-talos-installer@sha256:c0fe6ec4eb157ab8d993477b7b85abc982dc1ecbd7a9fb3cc0bcb054159fda8e
talosctl -n <node> patch mc --mode no-reboot \
  -p '{"machine":{"install":{"image":"ghcr.io/roysbike/mixtile-talos-installer@sha256:c0fe6ec4eb157ab8d993477b7b85abc982dc1ecbd7a9fb3cc0bcb054159fda8e"}}}'
```

* **По одному узлу.** Перед следующим: в etcd все участники, реплики
  хранилища (DRBD) синхронны, базы данных здоровы.
* **Оставляйте drain по умолчанию** (без `--drain=false`). Обновление без
  drain оставило реплики DRBD работающей базы в разном состоянии и
  повредило её ext4.
* **Узел с primary базы данных (CloudNativePG) сначала cordon** и
  дождитесь переключения.
* **Всегда передавайте `--image` и держите `machine.install.image` равным
  ему.** `talosctl upgrade` без `--image` ставит то, что записано в этом
  поле. Не задавайте `machine.install.grubUseUKICmdline: false`: со старым
  образом в `machine.install.image` это загрузило ядро, которое отвергло
  модуль openmiop.
* Откат: `talosctl -n <node> rollback`.

## Проверка

```sh
talosctl -n <node> version                        # Tag: v1.14.4
talosctl -n <node> get extensions                 # openmiop 0.6.1-v1.14.4, drbd, zfs, ...
talosctl -n <node> dmesg | grep openmiop          # "peer N up, 4 queues, doorbell, checksum offload"
talosctl -n <node> get links | grep omi0          # alias omi0, up
talosctl -n <node> get kernelmodulestatus | grep blade3   # blade3_leds, blade3_nvme_recover
ping -c3 -M do -s 8972 10.20.0.<N>                # jumbo-кадр с другого участника фабрики
```

`scripts/openmiop-verify.sh <node-ip>` выполняет эти проверки разом. В
логе ядра один раз появляется `module verification failed: signature
and/or required key missing - tainting kernel`; см. ниже.

## Технические подробности

**Изменения device tree для Cluster Box** (поверх device tree Blade 3 от
Armbian; каждое изменение прокомментировано в
`artifacts/dtb/blade3/rk3588-mixtile-blade3.dts`):

| Изменение | Зачем |
| --- | --- |
| Контроллер PCIe3 x4 `fe150000` как endpoint `pcie3x4_ep` (2 линии, compatible `openmiop,rk3588-pcie-ep`), host `pcie3x4` выключен | линии 0-1 идут на коммутатор Cluster Box; openmiop сам управляет контроллером (DBI, iATU, eDMA), поэтому не mainline `rockchip,rk3588-pcie-ep` |
| Разделение PHY `data-lanes = <1 1 2 2>`, без общего refclk | линии 0-1 к коммутатору, 2-3 к M.2 NVMe; у шасси и блейда раздельные опорные частоты |
| NVMe на `pcie3x2` без `reset-gpios` | PERST# NVMe — это U.2 PERST# блейда, им управляет Cluster Box; `blade3-nvme-recover` возвращает NVMe после сброса шасси. NVMe работает в Gen3 x2 и переезжает в PCI-домен 0001 |
| PCIe SMMU (`mmu600_pcie`) выключен | трафик endpoint и чтения eDMA несут stream ID, которые не принадлежат ни одному устройству Linux |

**Подпись модулей.** Talos подписывает свои модули ключом, который
существует только во время официальной сборки ядра и потом уничтожается.
Модули openmiop собираются здесь на том же дереве ядра
(`artifacts/talos-kernel`, так же, как siderolabs/pkgs собирает внешние
модули: `modules_install` в `extras`, без отладочных символов) и
подписываются собственным ключом этой сборки, которому ядро не доверяет.
Поэтому образ загружается с `-module.sig_enforce`. Всё остальное (DRBD,
ZFS, …) — официальные подписанные сборки.

**Очереди на omi0.** Образ задаёт `sysctl.net.core.default_qdisc=fq` в
командной строке ядра, поэтому omi0 получает `mq` с `fq` на каждой из
четырёх очередей. Под нагрузкой задержка на omi0 остаётся ~0,4-0,9 мс
вместо ~3,5 мс с `pfifo_fast` (измерение в лаборатории, ping во время
четырёх TCP-потоков между двумя блейдами). Тот же
параметр в `machine.sysctls` срабатывает слишком поздно: модуль openmiop
создаёт omi0 в initramfs, до того как Talos применит конфигурацию машины.

**Конфигурация ядра.** Ядро — неизменённое ядро Talos ARM64.
`scripts/verify-kernel-config.sh` проверяет конфигурацию закреплённого
коммита пакетов Talos (хранилище, NVMe, VFIO, Realtek, netfilter для
Kubernetes). Часть этих драйверов — модули из initramfs, как в любом
образе Talos ARM64.

**Интеграция openmiop:** [docs/openmiop.md](docs/openmiop.md).
**Как overlay ложится на официальную раскладку Siderolabs**
(siderolabs/sbc-rockchip, pkgs, extensions): [docs/upstream.ru.md](docs/upstream.ru.md).

## Известные ограничения

* `module.sig_enforce` выключен (см. выше).
* Перезагрузка BMC сбрасывает все линки блейдов (~150 с, пока `omi-rc`
  не загрузится снова) и M.2 NVMe; блейды и NVMe восстанавливаются сами.
  С DRBD 9.3.4 перед плановой перезагрузкой BMC проверьте, что
  `out-of-sync` равен 0
  ([LINBIT/drbd#153](https://github.com/LINBIT/drbd/issues/153)), и на это
  время отключите проверку изоляции primary в CloudNativePG.
* BMC — шлюз блейдов в LAN: ~220-280 Мбит/с (процессор BMC). На трафик
  между блейдами это не влияет.
* ghcr.io иногда отказывает в скачивании образа во время `talosctl
  upgrade`; повтор помогает.
* Не проверено: отдельный Blade 3.

Сетевые ограничения openmiop:
[pcie-ep-net](https://github.com/roysbike/pcie-ep-net/blob/main/README.ru.md#известные-ограничения).

## Сборка

GitHub Actions (`.github/workflows/build-talos.yaml`) собирает на
нативном arm64 при каждом push в `claude/**` и `feat/**` (кроме изменений
только в документации) и для тегов `v*`:

1. overlay и расширение openmiop, публикуются в GHCR владельца
   репозитория;
2. установщик и образ диска;
3. проверки: U-Boot в секторе 64 образа диска, `scripts/verify-installer.sh`
   (ядро, расширения, модули openmiop и их `vermagic`, содержимое DTB,
   аргументы ядра), `BUILD-INFO.txt`, `SHA256SUMS`;
4. `_out/` как артефакт workflow (14 дней);
5. для тега — релиз на GitHub (`scripts/publish-release.sh`, текст из
   `docs/release-notes/<tag>.md`).

Локально (Docker с Buildx и эмуляцией arm64; намного медленнее CI):

```sh
docker login ghcr.io
USERNAME=<github-user-or-org> ./build.sh all        # или: overlay, image
```

Результаты — в `_out/`. Переопределения: `OUTPUT_DIR`, `REGISTRY`,
`IMAGE_TAG`, `TALOS_VERSION`; `OPENMIOP=0` собирает без openmiop и
оставляет `module.sig_enforce`; `PIN_EXTENSIONS=0` берёт теги расширений
вместо digest'ов. Makefile работает с GNU Make 3.81 из macOS.

## Структура репозитория

| Путь | Содержимое |
| --- | --- |
| `artifacts/blade3/u-boot/` | U-Boot 2026.07 для Blade 3 (defconfig, DTS) |
| `artifacts/dtb/blade3/` | device tree Blade 3 с изменениями PCIe для Cluster Box |
| `artifacts/arm-trusted-firmware/rk3588/`, `artifacts/rkbin/rk3588/` | TF-A и DDR-блоб |
| `artifacts/talos-kernel/` | дерево ядра Talos (конфигурация, патчи) для сборки модулей |
| `artifacts/openmiop/` | расширение openmiop (сборка модулей, манифест) |
| `installers/blade3/` | установщик overlay (размещение U-Boot, аргументы ядра) |
| `profiles/blade3/` | профиль образа диска |
| `build.sh`, `Makefile`, `Pkgfile` | точка входа сборки, сборка kres/bldr, версии |
| `scripts/` | `verify-installer.sh`, `verify-kernel-config.sh`, `openmiop-verify.sh`, `flash-blade3-macos.sh`, `publish-release.sh` |
| `docs/` | [интеграция openmiop](docs/openmiop.md), [официальная раскладка](docs/upstream.ru.md), [release notes](docs/release-notes/) |

Лицензия: [Mozilla Public License 2.0](LICENSE) (как у overlays
Siderolabs); модули openmiop — GPL-2.0 (pcie-ep-net).
