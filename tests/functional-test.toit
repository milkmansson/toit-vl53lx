// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import vl53lx.vl53l0x show *
import vl53lx.vl53l1x show *

import .mock-vl53l0x
import .mock-vl53l1x

/**
Functional checks of the parts of the drivers that the parity tests don't
  cover.  These only check the drivers against the simulated registers (and
  so against my own reading of the reference code), not against a real chip.
*/

test-l0x:
  registers := MockVl53l0xRegisters
  sensor := Vl53l0x (MockVl53l0xDevice registers)

  expect-equals 0xEE sensor.model-id

  measurement := sensor.read-measurement
  expect-equals 300 measurement.range-mm
  expect measurement.valid
  expect-equals "valid" measurement.status-name
  expect-equals 2.0 measurement.signal-rate-mcps
  expect-equals 0.5 measurement.ambient-rate-mcps
  expect-equals 10.0 measurement.effective-spads

  // Status decoding: (raw & 0x78) >> 3.
  [
    [0x08, Vl53l0x.STATUS-HARDWARE-FAIL],
    [0x20, Vl53l0x.STATUS-SIGNAL-FAIL],
    [0x30, Vl53l0x.STATUS-PHASE-FAIL],
    [0x40, Vl53l0x.STATUS-MIN-RANGE-FAIL],
    [0x00, Vl53l0x.STATUS-NO-UPDATE],
    [0x58, Vl53l0x.STATUS-VALID],
  ].do: | pair/List |
    registers.set-raw-status pair[0]
    expect-equals pair[1] sensor.read-measurement.status

  registers.set-raw-status 0x58
  registers.set-range 1234
  expect-equals 1234 sensor.read-range-mm

  sensor.set-interrupt-thresholds --low-mm=100 --high-mm=300
  thresholds := sensor.get-interrupt-thresholds
  expect-equals 100 thresholds[0]
  expect-equals 300 thresholds[1]

  sensor.set-range-offset-mm 25
  expect-equals 25.0 sensor.get-range-offset-mm
  sensor.set-range-offset-mm -25
  expect-equals -25.0 sensor.get-range-offset-mm

  sensor.set-crosstalk-rate-mcps 0.25
  expect-equals 0.25 sensor.get-crosstalk-rate-mcps

  sensor.set-profile Vl53l0x.PROFILE-HIGH-SPEED
  // The budget is quantised by the sensor's timeouts, so allow a small error.
  expect (((sensor.get-measurement-timing-budget) - 20_000).abs < 500)
  sensor.set-profile Vl53l0x.PROFILE-HIGH-ACCURACY
  expect (((sensor.get-measurement-timing-budget) - 200_000).abs < 500)

  expect-throw "OUT_OF_RANGE": sensor.set-address 0x80

test-l1x:
  mock := MockVl53l1xDevice
  sensor := Vl53l1x mock

  expect-equals 0xEACC sensor.model-id
  expect-equals Vl53l1x.DISTANCE-LONG sensor.get-distance-mode
  expect-equals 100 sensor.get-timing-budget-ms

  measurement := sensor.read-measurement
  expect-equals 300 measurement.distance-mm
  expect measurement.valid
  expect-equals 10.0 measurement.spad-count
  expect-equals 0x40 * 8 measurement.ambient-rate-kcps
  expect-equals 0x100 * 8 measurement.signal-rate-kcps

  // Status decoding, from ST's status table.
  [
    [9, Vl53l1x.STATUS-VALID],
    [6, Vl53l1x.STATUS-SIGMA-FAIL],
    [4, Vl53l1x.STATUS-SIGNAL-FAIL],
    [3, Vl53l1x.STATUS-HARDWARE-FAIL],
    [0, Vl53l1x.STATUS-NO-UPDATE],
  ].do: | pair/List |
    mock.set-raw-status pair[0]
    expect-equals pair[1] sensor.read-measurement.status

  expect-throw "OUT_OF_RANGE": sensor.set-timing-budget-ms 15  // Short mode only.
  expect-throw "OUT_OF_RANGE": sensor.set-distance-mode 3
  sensor.set-distance-mode Vl53l1x.DISTANCE-SHORT
  sensor.set-timing-budget-ms 15
  expect-equals 15 sensor.get-timing-budget-ms

main:
  test-l0x
  test-l1x
  print "OK: functional"
