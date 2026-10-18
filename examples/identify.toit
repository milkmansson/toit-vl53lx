// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// Run this first if you don't know which chip is on your board.
//
// It reads the ID registers and prints the raw bytes, which is useful if the
// chip turns out to be something this package doesn't know.

import i2c
import vl53lx show *

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  if not bus.test 0x29:
    print "Nothing answers at 0x29.  Check wiring, power, and that XSHUT is high."
    return
  device := bus.device 0x29
  id := identify device
  print id
  if id.is-vl53l0x: print "This is a VL53L0X.  Use Vl53l0x."
  else if id.is-vl53l1x: print "This is a VL53L1X.  Use Vl53l1x."
  else if id.kind == KIND-VL53L4CD: print "This is a VL53L4CD, which this package doesn't drive yet."
  else: print "Unknown chip.  Please report the raw bytes above."
