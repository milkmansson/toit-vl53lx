// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// Calibrates the offset of a VL53L0X or VL53L1X.
//
// Put a flat, matt, mid-grey target (a sheet of grey card works) exactly
// TARGET-MM in front of the sensor, then run this.  Write down the value it
// prints and apply it at start-up with set-range-offset-mm (VL53L0X) or
// set-offset-mm (VL53L1X); the sensors don't keep it over a power cycle.
// (I have not been able to try this on real hardware.)

import i2c
import vl53lx show *

TARGET-MM ::= 100

main:
  bus := i2c.Bus
      --sda=21
      --scl=22
  sensor := open (bus.device 0x29)
  print "Offset: $(sensor.calibrate-offset --target-mm=TARGET-MM) mm"
