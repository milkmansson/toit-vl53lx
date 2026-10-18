// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// Continuous ranging with a VL53L0X.  The sensor measures on its own every
// 100 ms; read-range-mm waits for the next result.

import i2c
import vl53lx show *

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  sensor := Vl53l0x (bus.device Vl53l0x.I2C-ADDRESS)
      --profile=Vl53l0x.PROFILE-HIGH-SPEED
  sensor.start-continuous --period-ms=100
  20.repeat:
    measurement := sensor.read-measurement
    if measurement.valid:
      print "$measurement.range-mm mm"
    else:
      print "no good reading ($measurement.status-name)"
  sensor.stop-continuous
