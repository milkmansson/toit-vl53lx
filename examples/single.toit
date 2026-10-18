// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// Single-shot ranging with whichever sensor is connected.

import i2c
import vl53lx show *

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  sensor := open (bus.device 0x29)
  10.repeat:
    print sensor.read-measurement
    sleep --ms=500
  sensor.close
