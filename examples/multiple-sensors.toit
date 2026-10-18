// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// Several VL53L0X (or VL53L1X) sensors on one bus.
//
// All sensors power up at 0x29.  Hold every XSHUT pin low, then release them
// one at a time and give each a new address before releasing the next.

import gpio
import i2c
import vl53lx show *

XSHUT-PINS ::= [16, 17]
FIRST-ADDRESS ::= 0x30

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  xshuts := XSHUT-PINS.map: | number/int |
    pin := gpio.Pin number --output
    pin.set 0
    pin
  sleep --ms=10

  sensors := []
  xshuts.size.repeat: | index/int |
    xshuts[index].set 1
    sleep --ms=10
    sensor := open (bus.device 0x29)
    sensor.set-address FIRST-ADDRESS + index
    // The first object keeps talking to 0x29, so open the sensor again.
    sensors.add (open (bus.device FIRST-ADDRESS + index))

  10.repeat:
    sensors.size.repeat:
      print "Sensor $it: $sensors[it].read-range-mm mm"
    sleep --ms=500
