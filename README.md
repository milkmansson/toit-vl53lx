# Toit vl53lx driver

Toit drivers for ST's time-of-flight distance sensors:

- `Vl53l0x` — VL53L0X, up to about 2 m, I2C address 0x29.
- `Vl53l1x` — VL53L1X, up to about 4 m, I2C address 0x29.
- `identify` / `open` — tell the two apart from their ID registers and give you the right driver.

> [!WARNING]
> Neither chip has a published register map; ST ships a C API instead.  These drivers are ports of the register sequences in that API as reproduced by open-source libraries (see [Sources](#sources)).  Use at your own risk.

## Wiring

| Breakout | ESP32 | Notes |
|---|---|---|
| VIN / 3V3 | 3V3 | Most breakouts have a regulator and level shifting; check yours. |
| GND | GND | |
| SDA, SCL | any I2C pins (examples: SDA 21, SCL 20) | |
| XSHUT | 3V3, or a GPIO | Active-low reset.  If left floating on a board without a pull-up the chip may stay in reset (Estimated).  Needed to change addresses, see `examples/multiple-sensors.toit`. |
| GPIO1 / INT | optional GPIO | Interrupt output, see `examples/l0x-interrupt.toit`. |

## Field of view and clearance

The sensors see a cone that widens with distance.

**Stated figures**:

- VL53L0X, about 25°: "Section 5 of the datasheet mentions that there is a 25 degree Field of View (FOV)" and "anything within the cone formed by that angle might be detected" ([Pololu forum](https://forum.pololu.com/t/vl53l0x-beam-width-angle/11483)).
- VL53L1X, 27° at full size and 15° at the smallest region of interest (ROI): "maximum FoV using 16x16 SPADs is 27 degrees and minimum FoV using 4x4 SPADs is 15 degrees". A reply adds: "these are 'diagonal' FoV numbers. If your target is moving along the centerline of the sensor, your test results will be closer to 10 degrees." ([ST community](https://community.st.com/t5/imaging-sensors/vl53l1x-reduced-fov/m-p/328703)). Another thread: "the sensor should see about 27° edge to edge (so 13.5° in any direction out from the center)" ([Pololu forum](https://forum.pololu.com/t/vl53l1x-fov-angle-limit/16307)).
- The ROI trades field of view for sensitivity: "allowing a smaller field of view (FoV) to be configured at the cost of losing some sensitivity" ([Pololu VL53L1X README](https://github.com/pololu/vl53l1x-arduino)). The default and maximum is 16x16, the minimum 4x4.

**Cone width at a given distance** (Estimated: calculated as 2 x distance x tan(angle / 2); not from a datasheet):

| Distance | L0X (25°) | L1X full ROI (27°) | L1X 4x4 ROI (15°) |
|---|---|---|---|
| 0.3 m | ~13 cm | ~14 cm | ~8 cm |
| 1 m | ~44 cm | ~48 cm | ~26 cm |
| 2 m | ~89 cm | ~96 cm | ~53 cm |

**Guidance**:

- Keep the whole cone clear. Anything inside it can be picked up: walls, shelf edges, cables. A closer object in the cone is likely to win over a farther target.
- The sources disagree on how much of the angle you can actually use, so leave 10-20% extra (Estimated).
- Behind a window or bezel, light reflected from it reaches the sensor and shows up as an error at short range. Keep the cover close to the sensor and clean. For the L1X, `calibrate-xtalk` is meant for this.
- To avoid clutter at the sides with an L1X, narrow the beam with `set-roi --width=4 --height=4`, at the cost of sensitivity. `set-roi --center` shifts the cone off-axis. The L0X has no ROI setting.
- Run `examples/identify.toit` first: which row applies depends on which chip your board has.

## Examples

In `examples/`: `identify`, `single`, `continuous`, `calibration`, `l0x-interrupt`,
`l1x-roi-thresholds`, `multiple-sensors`, and `distance-display`, which shows the
live distance as a large number and a scrolling plot on a 128x64 SSD1306
(needs the `pixel_display` and `ssd1306` packages; pins are in
`display-views.toit`).  The display drawing was checked by rendering it on a
simulated display, not on a real one.  It starts in long range mode and shows
a short code for the profile beside "mm": LR (long range), DEF, HS (high speed)
or HA (high accuracy) for a VL53L0X, and SR (short) or LR (long) for a
VL53L1X.  Change `L0X-PROFILE` or `L1X-DISTANCE-MODE` near the top of the file.

### Using a calibration offset with `distance-display`

1. Put a flat, matt, mid-grey target at a known distance in front of the sensor
   and set `TARGET-MM` in `examples/calibration.toit` to that distance. A target
   that is too close to the sensor may give a poor result (Estimated; check the
   datasheet for the minimum range).
2. Set `L0X-PROFILE` (VL53L0X) or `L1X-DISTANCE-MODE` (VL53L1X) in
   `calibration.toit` to the profile you will use for measuring, the same
   values as in `distance-display.toit`. Calibrate and measure with the same
   profile: a different profile may need a different offset (Estimated; not
   measured).
3. Run `calibration.toit`. It prints the profile it used, marked with `***`,
   then `Offset: ... mm`.
4. Paste that number into `OFFSET-MM` near the top of
   `examples/distance-display.toit`, for example `OFFSET-MM/num ::= -4.25`, and
   run it. The offset is added to every reading. Leave it at 0 for no correction.

The sensor forgets the offset when it loses power, so `distance-display` sets
it each time it starts. The VL53L0X keeps the value to 0.25 mm; the VL53L1X
rounds it to a whole millimetre. The calibration routine is written for this
driver and is not ST's own procedure; it has not been tried on real hardware.

## Which chip is on the board?

Run `examples/identify.toit`.  It prints the chip kind and the raw ID bytes:

| Chip | Register index | ID read | Source |
|---|---|---|---|
| VL53L0X | 8-bit, reg 0xC0 | `EE AA 10` (0xC0, 0xC1, 0xC2) | Adafruit's driver checks 0xC1 `!= 0xAA` and 0xC2 `!= 0x10` as well as 0xC0 |
| VL53L1X | 16-bit, reg 0x010F | `EA CC 10` | Adafruit's driver checks `model_id != 0xEA or module_type != 0xCC or mask_rev != 0x10` |
| VL53L4CD | 16-bit, reg 0x010F | `EB AA` | stm32duino VL53L4CD header: "should be 0xEBAA" — identified but **not driven** |

If it prints `unknown`, the raw bytes are your lead: paste them into an issue.
`identify` probes the VL53L0X first with a one-byte index, because writing a
two-byte index to a VL53L0X would write to its register 0x01.  That the
one-byte write is harmless to a VL53L1X is an assumption (*Untested*).

## Quick start

```toit
import i2c
import vl53lx show *

main:
  bus := i2c.Bus --sda=21 --scl=20
  sensor := open (bus.device 0x29)
  print sensor.read-measurement   // "312 mm (valid)"
```

## Feature coverage

| | VL53L0X | VL53L1X | VL53L4CD |
|---|---|---|---|
| Driver in this package | yes | yes | no (identified by `identify` only) |
| Maximum range (ST's figure, best case) | 2 m | 4 m | 1.2 m (see note) |
| Field of view (ST's figure) | about 25° (forum quoting the datasheet) | 27° typical, 15° with 4x4 ROI (forum) | 18° diagonal |
| Single-shot / continuous ranging | yes (continuous: back-to-back or timed) | yes (continuous or one-shot) | - |
| Status, signal and ambient rates, SPAD count | yes | yes | - |
| Timing budget | arbitrary, in µs | the ULD's fixed set: 15 (short only), 20, 33, 50, 100, 200, 500 ms | - |
| Inter-measurement period | `start-continuous --period-ms` | `set-inter-measurement-ms` | - |
| Distance mode / profiles | 4 profiles (default, long range, high speed, high accuracy) | short / long | - |
| VCSEL pulse periods | yes | via distance mode | - |
| Signal-rate limit | yes | signal and sigma thresholds | - |
| ROI | no | yes (4x4 to 16x16, centre selectable) | - |
| Interrupt config and thresholds | yes | yes (below / above / in / out window, on-no-target) | - |
| Offset and crosstalk | set/get and offset calibration | set/get, offset and crosstalk calibration | - |
| Change I2C address | yes | yes | - |
| Temperature recalibration | n/a | `update-temperature` | - |

Maximum ranges are quoted from ST's product pages
([VL53L0X](https://www.st.com/en/imaging-and-photonics-solutions/vl53l0x.html):
"It can measure absolute distances up to 2 m";
[VL53L1X](https://www.st.com/en/imaging-and-photonics-solutions/vl53l1x.html):
"accurate ranging up to 4 m";
[VL53L4CD](https://www.st.com/en/imaging-and-photonics-solutions/vl53l4cd.html):
"very accurate distance measurements from only 1 mm up to 1200 mm" and "Diagonal
FoV of 18°").  The VL53L4CD page's product table also lists "1.3" m, which
does not match its 1200 mm text, so 1.2 m is used here.  The L0X page gave no
field of view; the 25° figure is the forum quote in the field-of-view section.
These are ST's headline figures.  Estimated: real ranges are shorter in bright
light or with dark, small or angled targets.  The datasheets, which list the
conditions, were not consulted.

### Not implemented

- L0X: ST's sigma estimator and any other post-processing in ST's API that
  Pololu's library leaves out (the reference SPAD setup in init is done as
  Pololu does it).
- L1X: Pololu-style arbitrary timing budgets and its medium distance mode;
  only ST's ULD table is implemented.
- VL53L4CD, VL53L4CX, VL53L5CX, and other family members.
- XTALK calibration for L0X (only the crosstalk value is settable).

## Getting more range

What follows comes from the reference libraries' own comments where quoted. The
rest is Estimated and has not been tested on these boards.

**VL53L0X.**  Pololu's `Single.ino` has a `LONG_RANGE` option with the comments
"lower the return signal rate limit (default is 0.25 MCPS)" and "increase laser
pulse periods (defaults are 14 and 10 PCLKs)", and sets 0.1 MCPS and periods
of 18 and 14.  Its README warns that a lower limit "increases the potential
range of the sensor but also increases the likelihood of getting an inaccurate
reading because of reflections from objects other than the intended target."
In this driver:

```
sensor := Vl53l0x device --profile=Vl53l0x.PROFILE-LONG-RANGE
```

or `sensor.set-profile Vl53l0x.PROFILE-LONG-RANGE`.  You can also set
`set-signal-rate-limit` and `set-vcsel-pulse-period` yourself.  A longer
timing budget (`PROFILE-HIGH-ACCURACY` uses 200 ms) may help with weak returns
(Estimated), at the cost of speed.

**VL53L1X.**  Pololu's README says of the distance modes: "Shorter distance
modes are less affected by ambient light but have lower maximum ranges", and
"a longer timing budget allows for more accurate measurements."  So for range:
use `Vl53l1x.DISTANCE-LONG` (the default in this driver), a longer timing
budget such as 200 or 500 ms, and the full 16x16 ROI (narrowing the ROI costs
"some sensitivity", per the same README).  Raising the sigma threshold or
lowering the signal threshold (`set-sigma-threshold-mm`,
`set-signal-threshold-kcps`) should let weaker far returns through, at the cost
of more bad readings (Estimated from how the ULD uses them; untested).

**For any of them:**

- Use a large, light, matt target facing the sensor squarely.  Glossy or
  angled targets send light away from the sensor.
- Work in low infrared light.  Sunlight and some lamps reduce range a lot.
- Keep the cover glass clean and close to the sensor, and calibrate crosstalk
  on the VL53L1X if there is one.
- Average several readings; a single reading near the limit is noisy.

See "Reading noise" below if the readings of a stationary target jump around.

### Reading noise

Readings of a stationary target will scatter.  How much depends on the profile,
the target and the light.  Not all of this is documented for these sensors;
what is marked as quoted comes from the reference libraries, the rest is
Estimated and has not been tested on these boards.

**One data point.**  A VL53L0X in long range (`PROFILE-LONG-RANGE`) pointed at
a stationary target about 26 cm away, one reading per second, 27 readings, all
reported valid: lowest 242 mm, highest 279 mm, mean about 262 mm, standard
deviation about 11 mm.  This is one setup (one target, one lighting condition,
the default timing budget); it is not known whether this is typical.

**Why long range is likely noisier (Estimated, plus one quote).**
Long range lowers the signal limit from 0.25 to 0.1 MCPS and lengthens the
laser pulses.  Pololu's README says a lower limit "increases the likelihood of
getting an inaccurate reading because of reflections from objects other than
the intended target."  The timing budget is not changed by this profile, so
each reading still averages only a short measurement (Unverified: about 33 ms
by default).  The cone is also only about 12 cm wide at
26 cm (see the field-of-view table), so edges or surfaces beside the target
can pull a reading either way.  Bright infrared light, a dark or shiny target
and a nearby cover glass or bezel can add more.

**How to find out what is causing it:**

1. Compare profiles on the same target and distance: run `PROFILE-DEFAULT` and
   `PROFILE-HIGH-ACCURACY` (200 ms budget) as well as `PROFILE-LONG-RANGE`
   and compare the spread.  If the default profile is much steadier, long range
   is the cause.
2. Look at the signal and ambient rates.  `read-measurement` returns
   `signal-rate-mcps` and `ambient-rate-mcps`; a low signal or a high ambient
   rate points at the target or the light, not the driver.
3. Average several readings before you show or use a value.  The mean of
   many readings is far steadier than any one reading.

If the default profile is also noisy on a good target (large, light, matt,
square-on, in dim light), that could be a driver problem.  This cannot be
ruled out, because nothing here has run on a real sensor except the
simulation.

**Calibrate at a useful distance.**  The offset calibration is simplest at a
distance where the sensor is steady.  Very short distances are suspect
(Estimated), so calibrate at 150-200 mm, under the same profile you will measure
with.

## Known differences from the reference code

- L1X: the constructor waits for the boot-state register (0xE5) before
  configuring; the ULD doesn't.
- L1X: signed offsets are read back as signed, and calibrations avoid integer
  overflow.  The ULD appears to have bugs here (Estimated from reading its
  source), so these are *not* identical to it.  Not covered by the parity tests.
- Drivers are stateless apart from what the chip itself holds, and start no tasks.

## Sources

Used as the basis of the code (details and licences in [NOTICE.md](NOTICE.md)):

- Pololu VL53L0X library — https://github.com/pololu/vl53l0x-arduino
  (itself "based on the VL53L0X API provided by ST (STSW-IMG005)", per its licence file).
- ST VL53L1X Ultra Lite Driver, as shipped in SparkFun's library — https://github.com/sparkfun/SparkFun_VL53L1X_Arduino_Library (`src/st_src/`).
- Pololu VL53L1X library — https://github.com/pololu/vl53l1x-arduino

Consulted for cross-checking:

- Adafruit CircuitPython drivers — https://github.com/adafruit/Adafruit_CircuitPython_VL53L0X , https://github.com/adafruit/Adafruit_CircuitPython_VL53L1X
- STM32duino ports of ST's APIs — https://github.com/stm32duino/VL53L0X , https://github.com/stm32duino/VL53L1 , https://github.com/stm32duino/VL53L1X , https://github.com/stm32duino/VL53L4CD
- Field-of-view figures: the three forum threads linked in the field-of-view section above.
- Community register maps pointed out for this project (read earlier in the
  project; not used as code sources) — https://github.com/GrimbiXcode/VL53L0X-Register-Map , https://github.com/anisyanka/vl53l0x

ST's own documents: the VL53L0X API STSW-IMG005 and its user manual UM2039; the
VL53L1X Ultra Lite Driver user manual.

## Tests

The parity tests compare this driver against the reference libraries by running
both against the same simulated chip and diffing the register traces.  To
regenerate a golden trace, see `tests/trace-harness/README.md` (L0X) and
`tests/trace-harness-l1x/README.md` (L1X).

## Licence

MIT, see `LICENSE`.  Examples and tests are zero-clause BSD (`EXAMPLES_LICENSE`).
Derived code carries the original notices: `NOTICE.md`.

## Credits
- [Florian](https://github.com/floitsch) for the tireless help and encouragement
- The wider Toit developer team (past and present) for a truly excellent product

## About Toit
One would assume you are here because you know what Toit is.  If you dont:
> Toit is a high-level, memory-safe language, with container/VM technology built
> specifically for microcontrollers (not a desktop language port). It gives fast
> iteration (live reloads over Wi-Fi in seconds), robust serviceability, and
> performance that’s far closer to C than typical scripting options on the
> ESP32. [[link](https://toitlang.org/)]
- [Review on Soracom](https://soracom.io/blog/internet-of-microcontrollers-made-easy-with-toit-x-soracom/)
- [Review on eeJournal](https://www.eejournal.com/article/its-time-to-get-toit)
- Toit on [Wikipedia](https://en.wikipedia.org/wiki/Toit).
