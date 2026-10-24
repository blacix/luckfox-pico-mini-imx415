# Project Review Findings

Date: 2026-10-24

This document records source-level findings from reviewing the build and custom
runtime scripts. It does not claim that the image was rebuilt or that these
behaviors were reproduced on the device.

## Camera selection and `rkipc` startup

### Finding: the SC3336 build installs the IMX415 camera service and profile

**Severity: High — the selected camera and the userspace startup configuration
can disagree.**

`build.sh` accepts `sc3336` or `imx415`. The selection only changes which camera
node is enabled in the copied DTSI (`build.sh:83-95`). After that conditional,
the script unconditionally copies the custom init overlay, IMX415 INI, and
IMX415 IQ JSON into the SDK image overlay (`build.sh:100-113`). The overlay
contains `S99a-eye-cam` and `rkipc-supervisor.sh`.

Those scripts are IMX415-specific:

- `overlay/a-eye/etc/init.d/S99a-eye-cam:6-7` requires the IMX415 INI and IQ
  file. Its `start` path stops any existing `rkipc` process before launching
  the custom supervisor (`:9-20`, `:52-59`).
- `overlay/a-eye/usr/bin/rkipc-supervisor.sh:3-6` selects the IMX415 INI and
  IQ file, and `:46-61` repeatedly launches `rkipc` with those paths.

Consequently, a `./build.sh sc3336` image still installs a service that can
stop the stock `rkipc` and restart it with IMX415 settings. Selecting SC3336 in
the DTSI alone does not preserve the stock SC3336 userspace configuration.

### Finding: stock SC3336 startup is a specific setup flow, not just bare `rkipc`

The SDK's `RkLunch.sh` loads kernel modules, detects `sc3336`, chooses
`/oem/usr/share/rkipc-300w.ini`, copies the selected factory INI to
`/userdata/rkipc.ini`, and launches `rkipc -a /oem/usr/share/iqfiles`
(`sdk/luckfox-pico/project/app/rkipc/rkipc/src/rv1103_ipc/RkLunch.sh:58-65`,
`:71-110`, `:117-121`). The SDK's `rkipc` help also documents its built-in
defaults as `/userdata/rkipc.ini` and `/etc/iqfiles`
(`sdk/luckfox-pico/project/app/rkipc/rkipc/src/rv1103_ipc/main.c:50-53`), but
the stock launcher explicitly supplies the OEM IQ directory.

For SC3336, the intended owner should remain the SDK stock startup flow, unless
the project deliberately takes over the equivalent INI selection/copy and IQ
path behavior. Installing the current IMX415 service does neither.

### Finding: both startup paths may compete for the `rkipc` process

The custom camera service kills any process named `rkipc` before starting its
supervisor (`S99a-eye-cam:9-20`, `:47-59`). The SDK launcher starts `rkipc`
after its stock setup (`RkLunch.sh:105-121`). The current build installs the
custom service for either camera selection, so the image has two distinct
startup mechanisms with different configuration paths. Exact ordering and
whether both execute on a given image have not been verified on-device.

### Suggested correction

Make the rootfs camera startup/configuration follow the same camera selection
as the DTSI:

- **IMX415:** install the custom camera init service, supervisor, INI, and IQ
  file; let the custom service own `rkipc`.
- **SC3336:** omit the IMX415 camera service/supervisor and IMX415-only config
  files, leaving the SDK stock launcher to choose its SC3336 INI and IQ path.

The shared LED test files can remain installed for either build, subject to the
LED-specific findings below.

## Custom LED and camera runtime scripts

### Finding: LED test signal trap does not stop the loop on `INT` or `TERM`

**Severity: Medium — a stop request can leave the LED test running.**

`overlay/a-eye/usr/bin/test-pwm-led.sh:21` assigns the same brightness-reset
command to `EXIT`, `INT`, and `TERM`. The `INT`/`TERM` handlers do not exit the
script, so after handling a signal the loop at `:23-28` can continue. The init
script tries `TERM`, waits one second, then escalates to `KILL`
(`overlay/a-eye/etc/init.d/S99a-eye-led:41-50`), which masks the issue with a
forced kill rather than allowing normal shutdown.

### Finding: supervisor log grows without a size limit

**Severity: Low — repeated `rkipc` failures can consume writable storage.**

`overlay/a-eye/usr/bin/rkipc-supervisor.sh:7` writes to `/tmp/rkipc.log`; each
launch and failure appends to that file (`:15`, `:47-60`). The supervisor retries
forever every five seconds, with no rotation or truncation, so a persistent
failure can grow the log for the lifetime of the device.

### Finding: LED init script is coupled to the IMX415 module

`overlay/a-eye/etc/init.d/S99a-eye-led:4`, `:19-25` attempts to load
`/oem/usr/ko/imx415.ko` before starting a PWM LED test. The LED test itself
operates on `/sys/class/leds/pwm0_led` (`overlay/a-eye/usr/bin/test-pwm-led.sh:6-9`)
and does not use the camera module. This makes the LED service camera-specific
even though the tested LED is independent of the camera. On an SC3336 image,
the IMX415 module may be absent or inappropriate; this coupling should be
removed or made conditional if the LED test is intended to work for both
camera builds.

## Verification status

These findings come from reading the tracked build script, overlay scripts,
and SDK startup source. No image build, shellcheck run, or device-side test was
performed as part of this review.
