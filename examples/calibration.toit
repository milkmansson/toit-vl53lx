// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

/**
Calibrates the offset of a VL53L0X or VL53L1X.

Put a flat, matt, mid-grey target (a sheet of grey card works) exactly
  TARGET-MM in front of the sensor, then run this.  Write down the value it
  prints and apply it at start-up with set-range-offset-mm (VL53L0X) or
  set-offset-mm (VL53L1X); the sensors don't keep it over a power cycle.

The offset is measured with the profile set below, and the output says which
  one.  Use the same profile when you apply the offset, for example the same
  values of L0X-PROFILE and L1X-DISTANCE-MODE in distance-display.toit.  A
  different profile may need a different offset (Estimated; not measured).
*/

import i2c
import vl53lx show *

TARGET-MM ::= 70

// The ranging profile of a VL53L0X: Vl53l0x.PROFILE-DEFAULT,
// Vl53l0x.PROFILE-LONG-RANGE, Vl53l0x.PROFILE-HIGH-SPEED or
// Vl53l0x.PROFILE-HIGH-ACCURACY.
L0X-PROFILE ::= Vl53l0x.PROFILE-LONG-RANGE

// The distance mode of a VL53L1X: Vl53l1x.DISTANCE-SHORT or
// Vl53l1x.DISTANCE-LONG.
L1X-DISTANCE-MODE ::= Vl53l1x.DISTANCE-LONG

L0X-PROFILE-NAMES ::= ["default", "long range", "high speed", "high accuracy"]
L0X-PROFILE-CODES ::= ["DEF", "LR", "HS", "HA"]

main:
  bus := i2c.Bus
      --sda=21
      --scl=20
  sensor := open (bus.device 0x29)
  chip/string := ?
  profile-name/string := ?
  profile-code/string := ?
  if sensor is Vl53l0x:
    sensor.set-profile L0X-PROFILE
    chip = "VL53L0X"
    profile-name = L0X-PROFILE-NAMES[L0X-PROFILE]
    profile-code = L0X-PROFILE-CODES[L0X-PROFILE]
  else:
    sensor.set-distance-mode L1X-DISTANCE-MODE
    chip = "VL53L1X"
    long := L1X-DISTANCE-MODE == Vl53l1x.DISTANCE-LONG
    profile-name = long ? "long range" : "short range"
    profile-code = long ? "LR" : "SR"
  print "Calibrating a $chip with a target at $TARGET-MM mm."
  print "*** PROFILE: $profile-name ($profile-code) ***"
  offset := sensor.calibrate-offset --target-mm=TARGET-MM
  print "Offset: $offset mm"
  print "*** Measured with profile $profile-name ($profile-code).  Use the same profile when you apply this offset. ***"
