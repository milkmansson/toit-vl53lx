// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import vl53lx.vl53l1x show *

import .golden-vl53l1x
import .mock-vl53l1x

/**
Checks that this driver makes the same register accesses as ST's VL53L1X Ultra
  Lite Driver (as shipped in SparkFun's library), which is known to work on
  real hardware.

One intended difference: this driver reads the boot-state register (0xE5)
  before anything else, to wait for the sensor to boot.  That read is removed
  from the trace before comparing.

Another: when the stored timing budget isn't a known value, ST's
  set-distance-mode still calls its timing-budget setter, which reads the
  mode register and then does nothing.  This driver skips that call.  So
  identical consecutive read lines are collapsed in both traces.
*/

collapse-reads_ lines/List -> List:
  result := []
  lines.do: | line/string |
    repeated := not result.is-empty and result.last == line and line.starts-with "R "
    if not repeated: result.add line
  return result

run-scenario mock/MockVl53l1xDevice -> none:
  mock.mark "init"
  sensor := Vl53l1x mock

  mock.mark "timing-100"
  sensor.set-timing-budget-ms 100
  mock.mark "get-timing"
  mock.mark "timing $sensor.get-timing-budget-ms"

  mock.mark "mode-short"
  sensor.set-distance-mode Vl53l1x.DISTANCE-SHORT
  mock.mark "get-mode"
  mock.mark "mode $sensor.get-distance-mode"

  mock.mark "timing-33"
  sensor.set-timing-budget-ms 33

  mock.mark "mode-long"
  sensor.set-distance-mode Vl53l1x.DISTANCE-LONG

  mock.mark "timing-200"
  sensor.set-timing-budget-ms 200
  mock.mark "timing $sensor.get-timing-budget-ms"

  mock.mark "inter-measurement-120"
  sensor.set-inter-measurement-ms 120
  mock.mark "inter-measurement $sensor.get-inter-measurement-ms"

  mock.mark "roi-8x8"
  sensor.set-roi --width=8 --height=8 --center=150
  size := sensor.get-roi-size
  mock.mark "roi-x $size[0]"
  mock.mark "roi-y $size[1]"

  mock.mark "roi-16x16"
  sensor.set-roi --width=16 --height=16 --center=100
  size = sensor.get-roi-size
  mock.mark "roi-x $size[0]"
  mock.mark "roi-y $size[1]"

  mock.mark "offset"
  sensor.set-offset-mm -12

  mock.mark "xtalk"
  sensor.set-xtalk-cps 500
  mock.mark "xtalk $sensor.get-xtalk-cps"

  mock.mark "thresholds"
  sensor.set-distance-threshold --low-mm=100 --high-mm=300 --window=2 --no-on-no-target
  mock.mark "window $sensor.get-distance-threshold-window"
  mock.mark "low $sensor.get-distance-threshold-low-mm"
  mock.mark "high $sensor.get-distance-threshold-high-mm"

  mock.mark "thresholds-no-target"
  sensor.set-distance-threshold --low-mm=50 --high-mm=400 --window=3 --on-no-target

  mock.mark "signal-sigma"
  sensor.set-signal-threshold-kcps 1024
  mock.mark "signal $sensor.get-signal-threshold-kcps"
  sensor.set-sigma-threshold-mm 90
  mock.mark "sigma $sensor.get-sigma-threshold-mm"

  mock.mark "polarity-low"
  sensor.set-interrupt-polarity --no-active-high
  mock.mark "polarity $(sensor.is-interrupt-active-high ? 1 : 0)"

  mock.mark "polarity-high"
  sensor.set-interrupt-polarity --active-high
  mock.mark "polarity $(sensor.is-interrupt-active-high ? 1 : 0)"

  mock.mark "ranging"
  sensor.start-ranging
  mock.mark "ready $(sensor.is-data-ready ? 1 : 0)"
  mock.mark "distance $sensor.read-distance-mm"
  sensor.clear-interrupt
  sensor.stop-ranging

  mock.mark "oneshot"
  sensor.start-oneshot

  mock.mark "temperature"
  sensor.update-temperature

  mock.mark "set-address"
  sensor.set-address 0x30

main:
  mock := MockVl53l1xDevice
  run-scenario mock
  actual := collapse-reads_ (mock.trace.filter: it != "R 00E5 1")
  golden := GOLDEN-VL53L1X-TRACE.trim --right "\n"
  expected := collapse-reads_ (golden.split "\n")

  mismatch := -1
  limit := min actual.size expected.size
  limit.repeat:
    if mismatch < 0 and actual[it] != expected[it]: mismatch = it
  if mismatch < 0 and actual.size != expected.size: mismatch = limit
  if mismatch >= 0:
    start := max 0 (mismatch - 4)
    print "Trace differs from ST's at line $(mismatch + 1):"
    (min (mismatch + 5) (max actual.size expected.size)).repeat: | index |
      if index >= start:
        got := index < actual.size ? actual[index] : "<end>"
        want := index < expected.size ? expected[index] : "<end>"
        print "  $(index == mismatch ? ">>" : "  ") got: $got | want: $want"
    throw "VL53L1X trace differs from the ST trace"
  print "OK: $actual.size lines match ST's Ultra Lite Driver."
  expect-equals 0xEACC (Vl53l1x mock).model-id
