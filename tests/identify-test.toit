// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import expect show *
import serial
import vl53lx show *

import .mock-vl53l0x
import .mock-vl53l1x

class SilentDevice implements serial.Device:
  registers -> serial.Registers: throw "UNIMPLEMENTED"
  read amount/int -> ByteArray: throw "no device"
  write bytes/ByteArray -> none: throw "no device"

main:
  l0 := MockVl53l0xDevice MockVl53l0xRegisters
  id := identify l0
  expect-equals KIND-VL53L0X id.kind
  expect (open l0) is Vl53l0x

  l1 := MockVl53l1xDevice
  id = identify l1
  expect-equals KIND-VL53L1X id.kind
  expect (open l1) is Vl53l1x

  id = identify SilentDevice
  expect-equals KIND-UNKNOWN id.kind
  expect-throw "Unsupported or missing sensor: unknown": open SilentDevice

  print "OK: identify"
