# Night-vision threshold measurements

This log records controlled brightness measurements from the IMX415 camera via
`/usr/bin/night-vision-measurement`. The night-vision controller was stopped
during capture so it could not change the LED or IR-cut state. Each condition used five
samples, about two seconds apart. The camera reported 1280x720 frames and
sampled a 160x90 grid (14,400 pixels).

## 2026-10-26: one-lamp room

The room was lit by one ceiling lamp. The first capture was taken with the
day/normal optical state. The second used the night-mode optical state while
the room lighting remained unchanged.

### Normal light: IR-cut off, IR LED off

- GPIO116: `1` (IR-cut off/day position)
- IR LED: `0` / `255`
- Five samples, approximately two seconds apart

```json
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.403,"p10_y":45,"p50_y":102,"p90_y":131,"min_y":7,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.578,"p10_y":45,"p50_y":102,"p90_y":131,"min_y":7,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.578,"p10_y":45,"p50_y":102,"p90_y":131,"min_y":7,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.605,"p10_y":45,"p50_y":102,"p90_y":131,"min_y":7,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.570,"p10_y":45,"p50_y":102,"p90_y":131,"min_y":7,"max_y":249}
```

Summary: mean_y `96.403–96.605` (average `96.547`); p10_y `45`; p50_y `102`;
p90_y `131`.

### Same one-lamp room: IR-cut on, IR LED on

GPIO116 was switched low and the PWM IR LED was set to 127/255. The state was
left to settle for five seconds before sampling.

- GPIO116: `0` (IR-cut on/night position)
- IR LED: `127` / `255`
- Five samples, approximately two seconds apart

```json
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":102.518,"p10_y":80,"p50_y":102,"p90_y":121,"min_y":51,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":102.412,"p10_y":80,"p50_y":102,"p90_y":121,"min_y":48,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":102.406,"p10_y":80,"p50_y":102,"p90_y":121,"min_y":50,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":102.465,"p10_y":80,"p50_y":102,"p90_y":121,"min_y":50,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":102.405,"p10_y":80,"p50_y":102,"p90_y":121,"min_y":48,"max_y":249}
```

Summary: mean_y `102.405–102.518` (average `102.441`); p10_y `80`; p50_y
`102`; p90_y `121`.

The second state is the one-lamp scene with the night-mode IR-cut and IR LED
active. The IR LED state changes the measured image statistics, so this result
should be compared with the dark-room capture in the same hardware state. It
is not a measurement of ambient light alone.

## Dark-room measurements

The ceiling light was off. The PC monitor remained on and provided some light;
the room was described as already dark enough. GPIO116 and the LED were
verified before capture. The controller remained stopped.

### Dark room: IR-cut on, IR LED on

- GPIO116: `0` (IR-cut on/night position)
- IR LED: `127` / `255`
- Five samples, approximately two seconds apart
- No additional state change or settling delay was needed after the one-lamp
  night-state measurement; this state was already active.

```json
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":99.315,"p10_y":81,"p50_y":100,"p90_y":113,"min_y":61,"max_y":247}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":99.253,"p10_y":81,"p50_y":100,"p90_y":113,"min_y":61,"max_y":247}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":99.242,"p10_y":81,"p50_y":100,"p90_y":113,"min_y":61,"max_y":247}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":99.248,"p10_y":81,"p50_y":100,"p90_y":113,"min_y":61,"max_y":247}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":99.209,"p10_y":81,"p50_y":100,"p90_y":113,"min_y":60,"max_y":247}
```

Summary: mean_y `99.209–99.315` (average `99.253`); p10_y `81`; p50_y `100`;
p90_y `113`.

### Dark room: IR-cut off, IR LED off

The ceiling light remained off and the PC monitor remained on. GPIO116 was
switched high, the LED was turned off, and the image was allowed to settle for
five seconds before sampling.

- GPIO116: `1` (IR-cut off/day position)
- IR LED: `0` / `255`
- Five samples, approximately two seconds apart

```json
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":23.239,"p10_y":2,"p50_y":22,"p90_y":43,"min_y":1,"max_y":200}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":22.611,"p10_y":2,"p50_y":22,"p90_y":41,"min_y":1,"max_y":185}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":23.108,"p10_y":2,"p50_y":22,"p90_y":42,"min_y":1,"max_y":187}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":21.180,"p10_y":2,"p50_y":21,"p90_y":40,"min_y":1,"max_y":184}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":21.838,"p10_y":2,"p50_y":21,"p90_y":40,"min_y":1,"max_y":183}
```

Summary: mean_y `21.180–23.239` (average `22.395`); p10_y `2`; p50_y
`21–22`; p90_y `40–43`.

### Dark room: night IR-cut position, IR LED off

The ceiling light remained off and the PC monitor remained on. GPIO116 was
switched low while the IR LED stayed off; the image was allowed to settle for
five seconds before sampling.

- GPIO116: `0` (night IR-cut position)
- IR LED: `0` / `255`
- Five samples, approximately two seconds apart

```json
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":30.268,"p10_y":3,"p50_y":27,"p90_y":52,"min_y":1,"max_y":210}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":26.346,"p10_y":2,"p50_y":23,"p90_y":46,"min_y":1,"max_y":195}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":25.889,"p10_y":2,"p50_y":23,"p90_y":45,"min_y":1,"max_y":194}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":26.737,"p10_y":2,"p50_y":24,"p90_y":46,"min_y":1,"max_y":194}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":24.952,"p10_y":2,"p50_y":22,"p90_y":45,"min_y":1,"max_y":191}
```

Summary: mean_y `24.952–30.268` (average `26.838`); p10_y `2–3`; p50_y
`22–27`; p90_y `45–52`.

### One-lamp room: night IR-cut position, IR LED off

The same ceiling lamp used for the earlier one-lamp measurements was on. GPIO116
remained low, the IR LED remained off, and the camera was allowed to settle for
five seconds before sampling.

- GPIO116: `0` (night IR-cut position)
- IR LED: `0` / `255`
- Five samples, approximately two seconds apart

```json
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":95.497,"p10_y":51,"p50_y":100,"p90_y":129,"min_y":8,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":95.697,"p10_y":51,"p50_y":101,"p90_y":129,"min_y":8,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":95.993,"p10_y":51,"p50_y":101,"p90_y":130,"min_y":8,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.211,"p10_y":51,"p50_y":101,"p90_y":130,"min_y":8,"max_y":249}
{"source_width":1280,"source_height":720,"sample_width":160,"sample_height":90,"samples":14400,"mean_y":96.408,"p10_y":51,"p50_y":101,"p90_y":130,"min_y":8,"max_y":249}
```

Summary: mean_y `95.497–96.408` (average `95.961`); p10_y `51`; p50_y
`100–101`; p90_y `129–130`.

## Summary across measured conditions

| Scene and hardware state | Mean `mean_y` | `p10_y` | `p50_y` | `p90_y` |
|---|---:|---:|---:|---:|
| One lamp, IR-cut off, LED off | 96.403–96.605 (avg 96.547) | 45 | 102 | 131 |
| One lamp, IR-cut on, LED on | 102.405–102.518 (avg 102.441) | 80 | 102 | 121 |
| Dark room with monitor glow, IR-cut on, LED on | 99.209–99.315 (avg 99.253) | 81 | 100 | 113 |
| Dark room with monitor glow, IR-cut off, LED off | 21.180–23.239 (avg 22.395) | 2 | 21–22 | 40–43 |
| Dark room with monitor glow, night IR-cut position, LED off | 24.952–30.268 (avg 26.838) | 2–3 | 22–27 | 45–52 |
| One lamp, night IR-cut position, LED off | 95.497–96.408 (avg 95.961) | 51 | 100–101 | 129–130 |

The dark and one-lamp night-state measurements use the same IR-cut and LED
settings. The monitor glow was present only in the dark-room measurement, so
that ambient light is part of its recorded condition.

## Comparison with the current switching thresholds

The configured rule enters night when `mean_y < 70`. It returns to day only
when both `mean_y > 90` and `p90_y` is in the inclusive range 105–180.

Both IR-lit captures meet the return-to-day rule:

| Scene | Average `mean_y` | `p90_y` | Return-to-day rule |
|---|---:|---:|---|
| One lamp, IR-cut on, LED on | 102.441 | 121 | Pass |
| Dark room with monitor glow, IR-cut on, LED on | 99.253 | 113 | Pass |
| One lamp, IR-cut off, LED off | 96.547 | 131 | Pass |
| Dark room with monitor glow, IR-cut off, LED off | 22.395 | 40–43 | Not applicable; night-entry test passes (`mean_y < 70`) |
| Dark room with monitor glow, night IR-cut position, LED off | 26.838 | 45–52 | Fails return-to-day test; remains night |
| One lamp, night IR-cut position, LED off | 95.961 | 129–130 | Pass |

Thus the `p90_y` acceptance band does not reject the measured dark, IR-lit
scene: its `p90_y` of 113 is inside the band, and its mean is above 90. These
measurements explain why the controller can classify the night hardware state
as day. In the dark day hardware state, `mean_y` is far below 70, so the
night-entry rule passes. This confirms the measured feedback loop: the day
state qualifies for night, then the night state qualifies for day because
both its mean and p90 values meet the return-to-day rule.

With the night IR-cut position retained but the IR LED off, the dark-room
average `mean_y` is 26.838, so it does not meet the return-to-day rule. In the
one-lamp scene with the same GPIO/LED state, average `mean_y` is 95.961 and
`p90_y` is 129–130, so both day conditions pass. These measurements support
using an LED-off frame for the decision, then restoring the LED for
illumination while remaining in night mode. This approach separates the two
measured lighting conditions with the existing thresholds.
