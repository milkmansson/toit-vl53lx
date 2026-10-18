# vl53lx

Toit drivers for ST's time-of-flight distance sensors:

- `Vl53l0x` — VL53L0X, up to about 2 m, I2C address 0x29.
- `Vl53l1x` — VL53L1X, up to about 4 m, I2C address 0x29.
- `identify` / `open` — tell the two apart from their ID registers and give you the right driver.

Neither chip has a published register map; ST ships a C API instead.  These
drivers are ports of the register sequences in that API as reproduced by
open-source libraries (see [Sources](#sources)).

## Status — read this first

**Nothing here has run on a real sensor yet.**  What has been checked, in simulation:

| Check | Result |
|---|---|
| `toit analyze` on all sources, examples, tests | clean |
| L0X: register trace of init + the operations in `tests/vl53l0x-parity-test.toit` vs Pololu's library | identical, 317 lines |
| L1X: register trace of init + the operations in `tests/vl53l1x-parity-test.toit` vs ST's Ultra Lite Driver | identical, 240 lines (two documented differences, see the test header) |
| Status decoding, thresholds, offset, crosstalk, profiles | `tests/functional-test.toit` |
| `identify` on simulated L0X / L1X / no device | `tests/identify-test.toit` |

"Identical trace" means the same bytes are written to the same registers in the
same order *when run against the same simulated chip*.  The simulation does not
model the optics, timing or the chip's reaction to a bad sequence, so this shows
the port is faithful to the reference code, not that the reference code or my
simulation matches the silicon.  Anything marked *untested* below is a guess.

Run the tests (from `tests/`): `toit pkg install --local ..` once, then
`toit run vl53l0x-parity-test.toit` and likewise for the other `*-test.toit`.

## Wiring

| Breakout | ESP32 | Notes |
|---|---|---|
| VIN / 3V3 | 3V3 | Most breakouts have a regulator and level shifting; check yours. |
| GND | GND | |
| SDA, SCL | any I2C pins (examples: 21, 22) | |
| XSHUT | 3V3, or a GPIO | Active-low reset.  If left floating on a board without a pull-up the chip may stay in reset (my inference).  Needed to change addresses, see `examples/multiple-sensors.toit`. |
| GPIO1 / INT | optional GPIO | Interrupt output, see `examples/l0x-interrupt.toit`. |

## Which chip is on my board?

Run `examples/identify.toit`.  It prints the chip kind and the raw ID bytes:

| Chip | Register index | ID read | Source |
|---|---|---|---|
| VL53L0X | 8-bit, reg 0xC0 | `EE AA 10` (0xC0, 0xC1, 0xC2) | Adafruit's driver checks 0xC1 `!= 0xAA` and 0xC2 `!= 0x10` as well as 0xC0 |
| VL53L1X | 16-bit, reg 0x010F | `EA CC 10` | Adafruit's driver checks `model_id != 0xEA or module_type != 0xCC or mask_rev != 0x10` |
| VL53L4CD | 16-bit, reg 0x010F | `EB AA` | stm32duino VL53L4CD header: "should be 0xEBAA" — identified but **not driven** |

If it prints `unknown`, the raw bytes are your lead: paste them into an issue.
`identify` probes the VL53L0X first with a one-byte index, because writing a
two-byte index to a VL53L0X would write to its register 0x01.  That the
one-byte write is harmless to a VL53L1X is my assumption, *untested*.

## Quick start

```toit
import i2c
import vl53lx show *

main:
  bus := i2c.Bus --sda=21 --scl=22
  sensor := open (bus.device 0x29)
  print sensor.read-measurement   // "312 mm (valid)"
```

## Feature coverage

| | VL53L0X | VL53L1X |
|---|---|---|
| Single-shot / continuous ranging | yes (continuous: back-to-back or timed) | yes (continuous or one-shot) |
| Status, signal and ambient rates, SPAD count | yes | yes |
| Timing budget | arbitrary, in µs | the ULD's fixed set: 15 (short only), 20, 33, 50, 100, 200, 500 ms |
| Inter-measurement period | `start-continuous --period-ms` | `set-inter-measurement-ms` |
| Distance mode / profiles | 4 profiles (default, long range, high speed, high accuracy) | short / long |
| VCSEL pulse periods | yes | via distance mode |
| Signal-rate limit | yes | signal and sigma thresholds |
| ROI | no | yes (4x4 to 16x16, centre selectable) |
| Interrupt config and thresholds | yes | yes (below / above / in / out window, on-no-target) |
| Offset and crosstalk | set/get and offset calibration | set/get, offset and crosstalk calibration |
| Change I2C address | yes | yes |
| Temperature recalibration | n/a | `update-temperature` |

### Not implemented

- L0X: ST's sigma estimator and any other post-processing in ST's API that
  Pololu's library leaves out (the reference SPAD setup in init is done as
  Pololu does it).
- L1X: Pololu-style arbitrary timing budgets and its medium distance mode;
  only ST's ULD table is implemented.
- VL53L4CD, VL53L4CX, VL53L5CX, and other family members.
- XTALK calibration for L0X (only the crosstalk value is settable).

## Known differences from the reference code

- L1X: the constructor waits for the boot-state register (0xE5) before
  configuring; the ULD doesn't.  Intentional, my choice.
- L1X: signed offsets are read back as signed, and calibrations avoid integer
  overflow.  I believe the ULD has bugs here (my reading of its source), so
  these are *not* identical to it.  Not covered by the parity tests.
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
- Community register maps pointed out for this project (read earlier in the
  project; not used as code sources) — https://github.com/GrimbiXcode/VL53L0X-Register-Map , https://github.com/anisyanka/vl53l0x

ST's own documents (not fetched in this work; I'm naming them from the
references' comments, so check the exact titles): the VL53L0X API STSW-IMG005
and its user manual UM2039; the VL53L1X Ultra Lite Driver user manual.

## Tests

The parity tests compare this driver against the reference libraries by running
both against the same simulated chip and diffing the register traces.  To
regenerate a golden trace, see `tests/trace-harness/README.md` (L0X) and
`tests/trace-harness-l1x/README.md` (L1X).

## Licence

MIT, see `LICENSE`.  Examples and tests are zero-clause BSD (`EXAMPLES_LICENSE`).
Derived code carries the original notices: `NOTICE.md`.
