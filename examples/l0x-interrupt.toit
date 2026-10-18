// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// VL53L0X: use the GPIO1 interrupt pin to wait for measurements instead of
// polling over I2C.  Connect GPIO1 on the breakout to pin 4 of the ESP32.

import gpio
import i2c
import vl53lx show *

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  interrupt := gpio.Pin 4 --input --pull-up
  sensor := Vl53l0x (bus.device Vl53l0x.I2C-ADDRESS)
  sensor.configure-interrupt Vl53l0x.GPIO-NEW-SAMPLE-READY
  sensor.start-continuous
  10.repeat:
    interrupt.wait-for 0  // The pin is active low by default.
    print "$sensor.read-range-mm mm"
  sensor.stop-continuous
