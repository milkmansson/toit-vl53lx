// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import vl53lx.vl53l0x show *

import .golden-vl53l0x
import .mock-vl53l0x

/**
Checks that this driver makes the same register accesses as Pololu's VL53L0X
  Arduino library, which is known to work on real hardware.

The golden trace was recorded by running that library against the same
  simulated chip.  See trace-harness/README.md.
*/

run-scenario registers/MockVl53l0xRegisters -> none:
  device := MockVl53l0xDevice registers

  registers.mark "init"
  sensor := Vl53l0x device
  registers.mark "init-result 1"
  registers.mark "get-budget"
  registers.mark "budget $sensor.get-measurement-timing-budget"

  registers.mark "single"
  registers.mark "range $sensor.read-range-mm"

  registers.mark "continuous-b2b"
  sensor.start-continuous
  registers.mark "range $sensor.read-range-mm"
  sensor.stop-continuous

  registers.mark "continuous-timed-100"
  sensor.start-continuous --period-ms=100
  registers.mark "range $sensor.read-range-mm"
  sensor.stop-continuous

  registers.mark "signal-rate-0.1"
  sensor.set-signal-rate-limit 0.1
  registers.mark "limit-micro $((sensor.get-signal-rate-limit * 1000000 + 0.5).to-int)"

  registers.mark "vcsel-pre-18"
  sensor.set-vcsel-pulse-period Vl53l0x.VCSEL-PRE-RANGE 18
  registers.mark "r 1"

  registers.mark "vcsel-final-14"
  sensor.set-vcsel-pulse-period Vl53l0x.VCSEL-FINAL-RANGE 14
  registers.mark "r 1"

  registers.mark "budget-200ms"
  sensor.set-measurement-timing-budget 200_000
  registers.mark "r 1"
  registers.mark "budget $sensor.get-measurement-timing-budget"

  registers.mark "budget-20ms"
  sensor.set-measurement-timing-budget 20_000
  registers.mark "r 1"
  registers.mark "budget $sensor.get-measurement-timing-budget"

  registers.mark "get-vcsel"
  registers.mark "pre $(sensor.get-vcsel-pulse-period Vl53l0x.VCSEL-PRE-RANGE) final $(sensor.get-vcsel-pulse-period Vl53l0x.VCSEL-FINAL-RANGE)"

  registers.mark "set-address"
  sensor.set-address 0x30

main:
  registers := MockVl53l0xRegisters
  run-scenario registers
  actual := registers.trace
  golden := GOLDEN-VL53L0X-TRACE.trim --right "\n"
  expected := golden.split "\n"

  mismatch := -1
  limit := min actual.size expected.size
  limit.repeat:
    if mismatch < 0 and actual[it] != expected[it]: mismatch = it
  if mismatch < 0 and actual.size != expected.size: mismatch = limit
  if mismatch >= 0:
    start := max 0 (mismatch - 4)
    print "Trace differs from Pololu's at line $(mismatch + 1):"
    (min (mismatch + 4) (max actual.size expected.size)).repeat: | index |
      if index >= start:
        got := index < actual.size ? actual[index] : "<end>"
        want := index < expected.size ? expected[index] : "<end>"
        print "  $(index == mismatch ? ">>" : "  ") got: $got | want: $want"
    throw "VL53L0X trace differs from the Pololu trace"
  print "OK: $actual.size lines match Pololu's library."
