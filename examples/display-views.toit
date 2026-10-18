// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import font show Font
import i2c
import pixel-display show *
import pixel-display.element show CustomElement
import pixel-display.two-color show WHITE BLACK
import ssd1306 show Ssd1306

/**
Drawing helpers for distance-display.toit.

They are written for a 128x64 monochrome SSD1306 or SSD1308 on I2C, in the
  same way as the helpers of the bmm350 examples.  The pixel_display package
  has no line call, so the lines here are drawn pixel by pixel.
*/

// The pins used by the bmm350 examples.  Change them to match your wiring.
SDA-PIN ::= 21
SCL-PIN ::= 20

DISPLAY-WIDTH ::= 128
DISPLAY-HEIGHT ::= 64

/** Whether a $rotation of 90 or 270 degrees gives a tall picture. */
is-portrait rotation/int -> bool:
  return rotation == 90 or rotation == 270

/** Opens the I2C bus on $SDA-PIN and $SCL-PIN.  The sensor and the display share it. */
open-bus -> i2c.Bus:
  return i2c.Bus
      --sda=SDA-PIN
      --scl=SCL-PIN
      --frequency=400_000

/**
Returns a display for the SSD1306 on the $bus, or throws if none answers.

The $rotation turns the picture clockwise by 0, 90, 180 or 270 degrees.
  $flip mirrors it top to bottom, which some modules need.  If black and white
  are swapped, add `--inverse` to the driver call below.
*/
open-display bus/i2c.Bus --rotation/int=0 --flip/bool=false -> PixelDisplay:
  if not [0, 90, 180, 270].contains rotation:
    throw "Display rotation must be 0, 90, 180 or 270, but was $rotation"
  if not (bus.test Ssd1306.I2C-ADDRESS):
    throw "No SSD1306 display found on the bus. Check the wiring."
  driver := Ssd1306.i2c (bus.device Ssd1306.I2C-ADDRESS) --flip=flip
  return display-for driver rotation

/** Returns a display on the $driver, with the picture turned by the $rotation. */
display-for driver/AbstractDriver rotation/int -> PixelDisplay:
  portrait := is-portrait rotation
  inverted := rotation == 0 or rotation == 270
  return PixelDisplay.two-color --portrait=portrait --inverted=inverted driver

draw-dot_ canvas/Canvas x/int y/int -> none:
  canvas.rectangle x y --w=1 --h=1 --color=WHITE

/** Draws a line from ($x0, $y0) to ($x1, $y1) in white (Bresenham). */
draw-line_ canvas/Canvas x0/int y0/int x1/int y1/int -> none:
  x := x0
  y := y0
  dx := (x1 - x0).abs
  dy := -(y1 - y0).abs
  step-x := x0 < x1 ? 1 : -1
  step-y := y0 < y1 ? 1 : -1
  error := dx + dy
  while true:
    draw-dot_ canvas x y
    if x == x1 and y == y1: break
    doubled := 2 * error
    if doubled >= dy:
      error += dy
      x += step-x
    if doubled <= dx:
      error += dx
      y += step-y

/**
A large seven-segment number.

Shows up to the number of digits given to the constructor, right aligned, without leading zeros.  Shows
  dashes when the value is null.
*/
class BigNumber extends CustomElement:
  // Segments a, b, c, d, e, f, g as bits 0..6.
  static SEGMENTS_ ::= [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]
  digits_/int
  digit-w_/int
  digit-h_/int
  gap_/int
  thickness_/int
  value_/int? := null

  type -> string: return "big-number"

  constructor --x/int=0 --y/int=0 --digits/int=4 --digit-w/int=18 --digit-h/int=30 --gap/int=3 --thickness/int=3:
    digits_ = digits
    digit-w_ = digit-w
    digit-h_ = digit-h
    gap_ = gap
    thickness_ = thickness
    super --x=x --y=y --w=(digits * (digit-w + gap) - gap) --h=digit-h

  /** Shows the $value, or dashes if it is null.  Values above the capacity show as all nines. */
  show value/int? -> none:
    if value == value_: return
    value_ = value
    invalidate

  custom-draw canvas/Canvas -> none:
    capacity := 1
    digits_.repeat: capacity *= 10
    text := ""
    if value_ != null:
      text = "$(min (max value_ 0) (capacity - 1))"
    digits_.repeat: | index/int |
      x := index * (digit-w_ + gap_)
      char-index := index - (digits_ - text.size)
      if value_ == null:
        // A dash in the middle of each digit.
        segment_ canvas x 6 0x40  // g only.
      else if char-index >= 0:
        segment_ canvas x 6 SEGMENTS_[text[char-index] - '0']

  segment_ canvas/Canvas x/int _/int mask/int -> none:
    t := thickness_
    w := digit-w_
    h := digit-h_
    half := h / 2
    if mask & 0x01 != 0: canvas.rectangle (x + t) 0 --w=(w - 2 * t) --h=t --color=WHITE              // a
    if mask & 0x02 != 0: canvas.rectangle (x + w - t) t --w=t --h=(half - t) --color=WHITE           // b
    if mask & 0x04 != 0: canvas.rectangle (x + w - t) half --w=t --h=(half - t) --color=WHITE        // c
    if mask & 0x08 != 0: canvas.rectangle (x + t) (h - t) --w=(w - 2 * t) --h=t --color=WHITE        // d
    if mask & 0x10 != 0: canvas.rectangle x half --w=t --h=(half - t) --color=WHITE                  // e
    if mask & 0x20 != 0: canvas.rectangle x t --w=t --h=(half - t) --color=WHITE                     // f
    if mask & 0x40 != 0: canvas.rectangle (x + t) (half - t / 2) --w=(w - 2 * t) --h=t --color=WHITE // g

/**
A scrolling plot of the most recent distances.

The newest sample is at the right.  The vertical scale runs from 0 at the
  bottom to the maximum given to the constructor at the top.  Samples that
  were not valid are left as gaps.
*/
class HistoryView extends CustomElement:
  width_/int
  height_/int
  max-mm_/int
  samples_/List  // Heights in pixels, or -1 for a gap.
  next_/int := 0

  type -> string: return "history-view"

  constructor --x/int=0 --y/int=34 --width/int=128 --height/int=30 --max-mm/int=1000:
    width_ = width
    height_ = height
    max-mm_ = max-mm
    samples_ = List (width - 2): -1
    super --x=x --y=y --w=width --h=height

  /** Adds a sample.  Use null for a reading that was not valid. */
  add distance-mm/int? -> none:
    if distance-mm == null:
      samples_[next_] = -1
    else:
      clamped := min (max distance-mm 0) max-mm_
      samples_[next_] = (clamped * (height_ - 3)) / max-mm_
    next_ = (next_ + 1) % samples_.size
    invalidate

  custom-draw canvas/Canvas -> none:
    draw-line_ canvas 0 0 (width_ - 1) 0
    draw-line_ canvas 0 (height_ - 1) (width_ - 1) (height_ - 1)
    draw-line_ canvas 0 0 0 (height_ - 1)
    draw-line_ canvas (width_ - 1) 0 (width_ - 1) (height_ - 1)
    previous/int? := null
    samples_.size.repeat: | column/int |
      sample := samples_[(next_ + column) % samples_.size]
      if sample < 0:
        previous = null
        continue.repeat
      y := height_ - 2 - sample
      if previous != null:
        draw-line_ canvas column previous (column + 1) y
      else:
        draw-dot_ canvas (column + 1) y
      previous = y

/** Returns a style for small white text. */
text-style -> Style:
  return Style --color=WHITE --font=(Font.get "sans10")
