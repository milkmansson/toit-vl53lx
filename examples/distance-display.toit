// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

// Live distance on a 128x64 SSD1306 display: a large number in millimetres and
// a scrolling plot of the last few seconds.  Works with a VL53L0X or a VL53L1X.
//
// The sensor and the display share one I2C bus.  The pins are in
// display-views.toit.  Wave a hand or a sheet of paper in front of the sensor
// and watch the trace.
//
// (Not tried on real hardware.  The drawing was checked on a simulated display.)

import vl53lx show *
import pixel-display show *
import pixel-display.two-color show BLACK

import .display-views

// Turns the picture on the display, clockwise, by 0, 90, 180 or 270 degrees.
DISPLAY-ROTATION ::= 0

// Mirrors the picture top to bottom.  Some display modules need it.
DISPLAY-FLIP ::= false

// The top of the plot, in millimetres.  The datasheet-style ranges are about
// 1200 mm for a VL53L0X and 4000 mm for a VL53L1X, but real ranges depend on the
// target and the light.  The default picks a value that suits indoor use.
PLOT-MAX-MM-L0X ::= 1200
PLOT-MAX-MM-L1X ::= 3000

main:
  bus := open-bus
  if not (bus.test 0x29):
    print "No VL53L0X/VL53L1X found at 0x29.  Check the wiring."
    return
  display := open-display bus --rotation=DISPLAY-ROTATION --flip=DISPLAY-FLIP
  sensor := open (bus.device 0x29)

  name/string := ?
  plot-max/int := ?
  if sensor is Vl53l0x:
    sensor.start-continuous
    name = "L0X"
    plot-max = PLOT-MAX-MM-L0X
  else:
    sensor.start-ranging
    name = "L1X"
    plot-max = PLOT-MAX-MM-L1X

  number := BigNumber --x=0 --y=0 --digits=4
  history := HistoryView --x=0 --y=34 --width=128 --height=30 --max-mm=plot-max
  unit := Label --x=84 --y=14 --text="mm" --style=text-style
  status := Label --x=84 --y=30 --text=name --style=text-style
  display.add
      Div --x=0 --y=0 --w=DISPLAY-WIDTH --h=DISPLAY-HEIGHT --background=BLACK [
          number,
          history,
          unit,
          status,
      ]

  last-draw := Time.monotonic-us
  last-print := last-draw
  while true:
    distance/int? := null
    valid := false
    status-text := ""
    if sensor is Vl53l0x:
      measurement := sensor.read-measurement
      distance = measurement.range-mm
      valid = measurement.valid
      status-text = measurement.status-name
    else:
      measurement := sensor.read-measurement
      distance = measurement.distance-mm
      valid = measurement.valid
      status-text = measurement.status-name

    // Every sample goes into the plot; invalid ones leave a gap.
    shown := valid ? distance : null
    history.add shown
    number.show shown

    now := Time.monotonic-us
    if now - last-draw >= 100_000:
      status.text = valid ? name : "$name ?"
      display.draw
      last-draw = now
    if now - last-print >= 1_000_000:
      print "$name: $distance mm ($status-text)"
      last-print = now
