// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// VL53L1X: narrow the field of view and report only when something is between
// 100 and 400 mm.

import i2c
import vl53lx show *

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  sensor := Vl53l1x (bus.device Vl53l1x.I2C-ADDRESS)
      --distance-mode=Vl53l1x.DISTANCE-SHORT
      --timing-budget-ms=50
      --inter-measurement-ms=60
  // 8x8 SPADs in the centre; the minimum is 4x4, the maximum 16x16.
  sensor.set-roi --width=8 --height=8
  sensor.set-distance-threshold --low-mm=100 --high-mm=400 --window=Vl53l1x.WINDOW-IN
  sensor.start-ranging
  20.repeat:
    measurement := sensor.read-measurement
    print "$measurement  signal: $measurement.signal-rate-kcps kcps"
  sensor.stop-ranging
