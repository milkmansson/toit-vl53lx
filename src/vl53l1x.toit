// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.
//
// Large parts of the register sequences in this file are derived from works
// licensed under the BSD 3-clause and MIT licences.  See NOTICE.md in the
// package root for the copyright notices and licence texts.

import io
import log
import serial

/**
Driver for the VL53L1X time-of-flight distance sensor.

The VL53L1X measures distances up to about 4 m (in the dark, with the long
  distance mode) and returns them in millimetres.  It has a programmable region
  of interest, so it can be aimed at part of its field of view.

The constructor waits for the sensor to boot, checks the model ID, loads the
  default configuration, and applies the given distance mode and timing
  budget.  It throws if the sensor does not answer or reports an unexpected
  model ID.

The simplest use is a single measurement:
```
bus := i2c.Bus --sda=(gpio.Pin 21) --scl=(gpio.Pin 22)
sensor := Vl53l1x (bus.device Vl53l1x.I2C-ADDRESS)
print "$sensor.read-range-mm mm"
```

For repeated measurements call $start-ranging once, then wait for $is-data-ready
  (or the interrupt pin) and read with $read-measurement.  Call
  $clear-interrupt after each reading, or use $read-range-mm and
  $read-measurement, which do it for you.

# Notes
The sensor has 16-bit register addresses.  This driver sends them as a write
  followed by a separate read, with a stop condition between them.
*/
class Vl53l1x:
  /** The default I2C address of the sensor (7-bit). */
  static I2C-ADDRESS ::= 0x29
  /** The model ID (model and module type bytes) of a VL53L1X. */
  static MODEL-ID ::= 0xEACC

  /** Distance mode with a shorter range (about 1.3 m), but better ambient light immunity. */
  static DISTANCE-SHORT ::= 1
  /** Distance mode with a longer range (up to about 4 m in the dark). */
  static DISTANCE-LONG ::= 2

  /** Interrupt when the distance is below the low threshold. */
  static WINDOW-BELOW ::= 0
  /** Interrupt when the distance is above the high threshold. */
  static WINDOW-ABOVE ::= 1
  /** Interrupt when the distance is outside the thresholds. */
  static WINDOW-OUT ::= 2
  /** Interrupt when the distance is inside the thresholds. */
  static WINDOW-IN ::= 3

  /** Measurement status: the range is valid. */
  static STATUS-VALID ::= 0
  /** Measurement status: the sigma (noise) estimate was above the limit. */
  static STATUS-SIGMA-FAIL ::= 1
  /** Measurement status: the returned signal was below the limit. */
  static STATUS-SIGNAL-FAIL ::= 2
  /** Measurement status: valid, but the range was clipped at the minimum range. */
  static STATUS-MIN-RANGE-CLIPPED ::= 3
  /** Measurement status: the phase was out of bounds. */
  static STATUS-OUT-OF-BOUNDS ::= 4
  /** Measurement status: a hardware failure was reported. */
  static STATUS-HARDWARE-FAIL ::= 5
  /** Measurement status: valid, but the wrap-around check could not be done. */
  static STATUS-VALID-NO-WRAP-CHECK ::= 6
  /** Measurement status: the target was wrapped (the real distance is likely larger). */
  static STATUS-WRAP-TARGET-FAIL ::= 7
  /** Measurement status: processing failure. */
  static STATUS-PROCESSING-FAIL ::= 8
  /** Measurement status: the signal was too weak compared to the crosstalk. */
  static STATUS-XTALK-SIGNAL-FAIL ::= 9
  /** Measurement status: a synchronization interrupt. */
  static STATUS-SYNCHRONIZATION-INT ::= 10
  /** Measurement status: valid, but the result is a merged pulse. */
  static STATUS-VALID-MERGED-PULSE ::= 11
  /** Measurement status: a target seems to be present, but with too little signal. */
  static STATUS-LACK-OF-SIGNAL ::= 12
  /** Measurement status: the target is closer than the minimum range. */
  static STATUS-MIN-RANGE-FAIL ::= 13
  /** Measurement status: invalid range. */
  static STATUS-INVALID ::= 14
  /** Measurement status: no update, or an unknown status code. */
  static STATUS-NO-UPDATE ::= 255

  // Register addresses.
  static REG-I2C-SLAVE-DEVICE-ADDRESS_ ::= 0x0001
  static REG-VHV-CONFIG-TIMEOUT-MACROP-LOOP-BOUND_ ::= 0x0008
  static REG-ALGO-CROSSTALK-COMPENSATION-PLANE-OFFSET-KCPS_ ::= 0x0016
  static REG-ALGO-CROSSTALK-COMPENSATION-X-PLANE-GRADIENT-KCPS_ ::= 0x0018
  static REG-ALGO-CROSSTALK-COMPENSATION-Y-PLANE-GRADIENT-KCPS_ ::= 0x001A
  static REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_ ::= 0x001E
  static REG-MM-CONFIG-INNER-OFFSET-MM_ ::= 0x0020
  static REG-MM-CONFIG-OUTER-OFFSET-MM_ ::= 0x0022
  static REG-GPIO-HV-MUX-CTRL_ ::= 0x0030
  static REG-GPIO-TIO-HV-STATUS_ ::= 0x0031
  static REG-SYSTEM-INTERRUPT-CONFIG-GPIO_ ::= 0x0046
  static REG-PHASECAL-CONFIG-TIMEOUT-MACROP_ ::= 0x004B
  static REG-RANGE-CONFIG-TIMEOUT-MACROP-A-HI_ ::= 0x005E
  static REG-RANGE-CONFIG-VCSEL-PERIOD-A_ ::= 0x0060
  static REG-RANGE-CONFIG-TIMEOUT-MACROP-B-HI_ ::= 0x0061
  static REG-RANGE-CONFIG-VCSEL-PERIOD-B_ ::= 0x0063
  static REG-RANGE-CONFIG-SIGMA-THRESH_ ::= 0x0064
  static REG-RANGE-CONFIG-MIN-COUNT-RATE-RTN-LIMIT-MCPS_ ::= 0x0066
  static REG-RANGE-CONFIG-VALID-PHASE-HIGH_ ::= 0x0069
  static REG-SYSTEM-INTERMEASUREMENT-PERIOD_ ::= 0x006C
  static REG-SYSTEM-THRESH-HIGH_ ::= 0x0072
  static REG-SYSTEM-THRESH-LOW_ ::= 0x0074
  static REG-SD-CONFIG-WOI-SD0_ ::= 0x0078
  static REG-SD-CONFIG-INITIAL-PHASE-SD0_ ::= 0x007A
  static REG-ROI-CONFIG-USER-ROI-CENTRE-SPAD_ ::= 0x007F
  static REG-ROI-CONFIG-USER-ROI-REQUESTED-GLOBAL-XY-SIZE_ ::= 0x0080
  static REG-SYSTEM-INTERRUPT-CLEAR_ ::= 0x0086
  static REG-SYSTEM-MODE-START_ ::= 0x0087
  static REG-RESULT-RANGE-STATUS_ ::= 0x0089
  static REG-RESULT-FINAL-CROSSTALK-CORRECTED-RANGE-MM-SD0_ ::= 0x0096
  static REG-RESULT-OSC-CALIBRATE-VAL_ ::= 0x00DE
  static REG-FIRMWARE-SYSTEM-STATUS_ ::= 0x00E5
  static REG-IDENTIFICATION-MODEL-ID_ ::= 0x010F

  // The default configuration for registers 0x2D to 0x87.  Most values are not
  // documented by the manufacturer.
  static DEFAULT-CONFIGURATION_ ::= #[
    0x00, 0x01, 0x01, 0x01, 0x02, 0x00, 0x02, 0x08,
    0x00, 0x08, 0x10, 0x01, 0x01, 0x00, 0x00, 0x00,
    0x00, 0xFF, 0x00, 0x0F, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x20, 0x0B, 0x00, 0x00, 0x02, 0x0A, 0x21,
    0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0xC8,
    0x00, 0x00, 0x38, 0xFF, 0x01, 0x00, 0x08, 0x00,
    0x00, 0x01, 0xDB, 0x0F, 0x01, 0xF1, 0x0D, 0x01,
    0x68, 0x00, 0x80, 0x08, 0xB8, 0x00, 0x00, 0x00,
    0x00, 0x0F, 0x89, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x0F, 0x0D, 0x0E, 0x0E, 0x00,
    0x00, 0x02, 0xC7, 0xFF, 0x9B, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x00,
  ]
  static CONFIG-FIRST-REGISTER_ ::= 0x2D

  // Timeout register values for each timing budget (in ms) as [A, B] pairs.
  static TIMING-SHORT_ ::= {
    15: [0x001D, 0x0027],
    20: [0x0051, 0x006E],
    33: [0x00D6, 0x006E],
    50: [0x01AE, 0x01E8],
    100: [0x02E1, 0x0388],
    200: [0x03E1, 0x0496],
    500: [0x0591, 0x05C1],
  }
  static TIMING-LONG_ ::= {
    20: [0x001E, 0x0022],
    33: [0x0060, 0x006E],
    50: [0x00AD, 0x00C6],
    100: [0x01CC, 0x01EA],
    200: [0x02D9, 0x02F8],
    500: [0x048F, 0x04A4],
  }

  device_/serial.Device
  logger_/log.Logger
  timeout-ms_/int
  ranging_/bool := false

  /**
  Constructs a driver for the VL53L1X on the given $device and initializes it.

  The $device is typically an I2C device at address $I2C-ADDRESS.

  If $io-2v8 is true (the default), the sensor's I2C and interrupt pins are
    configured to be pulled up to the 2.8 V supply (AVDD).  Many breakout
    boards expect this.  Set it to false for a 1.8 V bus.

  After loading the default configuration the constructor sets the $distance-mode
    ($DISTANCE-SHORT or $DISTANCE-LONG) and the $timing-budget-ms.  The
    $inter-measurement-ms, if given, sets the time between
    measurements in continuous mode.

  The $timeout-ms is the longest time to wait for the sensor in any operation.
  If $skip-id-check is true, an unexpected model ID is only logged.
  */
  constructor device/serial.Device
      --logger/log.Logger=log.default
      --io-2v8/bool=true
      --distance-mode/int=DISTANCE-LONG
      --timing-budget-ms/int=100
      --inter-measurement-ms/int?=null
      --timeout-ms/int=1000
      --skip-id-check/bool=false:
    device_ = device
    logger_ = logger.with-name "vl53l1x"
    timeout-ms_ = timeout-ms
    initialize_ io-2v8 skip-id-check
    set-distance-mode distance-mode
    set-timing-budget-ms timing-budget-ms
    if inter-measurement-ms != null: set-inter-measurement-ms inter-measurement-ms

  // Low-level register access.  The registers have 16-bit addresses.

  static address-bytes_ register/int -> ByteArray:
    bytes := ByteArray 2
    io.BIG-ENDIAN.put-uint16 bytes 0 register
    return bytes

  read-bytes_ register/int count/int -> ByteArray:
    device_.write (address-bytes_ register)
    return device_.read count

  write-bytes_ register/int data/ByteArray -> none:
    buffer := ByteArray 2 + data.size
    io.BIG-ENDIAN.put-uint16 buffer 0 register
    buffer.replace 2 data
    device_.write buffer

  read-u8_ register/int -> int:
    return (read-bytes_ register 1)[0]

  write-u8_ register/int value/int -> none:
    data := ByteArray 1
    data[0] = value & 0xFF
    write-bytes_ register data

  read-u16_ register/int -> int:
    return io.BIG-ENDIAN.uint16 (read-bytes_ register 2) 0

  write-u16_ register/int value/int -> none:
    bytes := ByteArray 2
    io.BIG-ENDIAN.put-uint16 bytes 0 (value & 0xFFFF)
    write-bytes_ register bytes

  read-u32_ register/int -> int:
    return io.BIG-ENDIAN.uint32 (read-bytes_ register 4) 0

  write-u32_ register/int value/int -> none:
    bytes := ByteArray 4
    io.BIG-ENDIAN.put-uint32 bytes 0 (value & 0xFFFFFFFF)
    write-bytes_ register bytes

  /** Waits until the $condition block returns true. */
  wait-for_ what/string [condition] -> none:
    deadline := Time.monotonic-us + (timeout-ms_ * 1000)
    while not condition.call:
      if Time.monotonic-us > deadline: throw "VL53L1X: timeout waiting for $what"
      sleep --ms=1

  // Initialization.

  initialize_ io-2v8/bool skip-id-check/bool -> none:
    // The sensor needs a moment after power-up (or reset) before it answers.
    wait-for_ "boot": ((read-u8_ REG-FIRMWARE-SYSTEM-STATUS_) & 0x01) != 0

    id := read-u16_ REG-IDENTIFICATION-MODEL-ID_
    if id != MODEL-ID:
      message := "VL53L1X: unexpected model ID 0x$(%04x id) (expected 0x$(%04x MODEL-ID))"
      if skip-id-check:
        logger_.warn message
      else:
        throw message

    // Load the default configuration, one register at a time.
    configuration := DEFAULT-CONFIGURATION_.copy
    if not io-2v8:
      configuration[0x2E - CONFIG-FIRST-REGISTER_] = 0x00  // I2C pulled up at 1.8 V.
      configuration[0x2F - CONFIG-FIRST-REGISTER_] = 0x00  // GPIO pulled up at 1.8 V.
    configuration.size.repeat:
      write-u8_ (CONFIG-FIRST-REGISTER_ + it) configuration[it]

    // Run a first ranging to let the sensor calibrate itself.  The first
    // measurement takes at least the default inter-measurement period (about
    // 100 ms).
    start-ranging
    wait-for_ "first measurement": is-data-ready
    clear-interrupt
    stop-ranging
    write-u8_ REG-VHV-CONFIG-TIMEOUT-MACROP-LOOP-BOUND_ 0x09  // Two bounds VHV.
    write-u8_ 0x000B 0  // Start VHV from the previous temperature.

  // Identification.

  /**
  Returns the model ID: the model byte in the high byte and the module type in
    the low byte.  A VL53L1X reports $MODEL-ID.
  */
  model-id -> int:
    return read-u16_ REG-IDENTIFICATION-MODEL-ID_

  /** Returns the mask revision register. */
  mask-revision -> int:
    return (read-bytes_ REG-IDENTIFICATION-MODEL-ID_ 3)[2]

  /** Returns the boot state register.  A non-zero value means the sensor has booted. */
  boot-state -> int:
    return read-u8_ REG-FIRMWARE-SYSTEM-STATUS_

  /**
  Changes the I2C address of the sensor to $new-address (7-bit).

  The change is lost when the sensor loses power or is reset with its XSHUT
    pin.  Afterwards the sensor answers on the new address, so the caller must
    open a new I2C device for it.  This object keeps using the old address.
  */
  set-address new-address/int -> none:
    if new-address < 0x08 or new-address > 0x77: throw "OUT_OF_RANGE"
    write-u8_ REG-I2C-SLAVE-DEVICE-ADDRESS_ (new-address & 0x7F)

  /** Stops ranging, if it is running. */
  close -> none:
    if ranging_: stop-ranging

  // Ranging control.

  /**
  Starts continuous ranging.

  The sensor then measures every inter-measurement period (see
    $set-inter-measurement-ms).  Read the results with $read-measurement,
    $read-range-mm or $read-distance-mm.
  */
  start-ranging -> none:
    write-u8_ REG-SYSTEM-INTERRUPT-CLEAR_ 0x01
    write-u8_ REG-SYSTEM-MODE-START_ 0x40
    ranging_ = true

  /**
  Starts one measurement.

  When it finishes, $is-data-ready becomes true.  Read the result with
    $read-measurement, $read-range-mm or $read-distance-mm.
  */
  start-oneshot -> none:
    write-u8_ REG-SYSTEM-INTERRUPT-CLEAR_ 0x01
    write-u8_ REG-SYSTEM-MODE-START_ 0x10

  /** Stops ranging. */
  stop-ranging -> none:
    write-u8_ REG-SYSTEM-MODE-START_ 0x00
    ranging_ = false

  /** Clears the interrupt, so that the sensor can signal the next measurement. */
  clear-interrupt -> none:
    write-u8_ REG-SYSTEM-INTERRUPT-CLEAR_ 0x01

  /** Whether a new measurement is ready to be read. */
  is-data-ready -> bool:
    polarity := interrupt-polarity_
    return ((read-u8_ REG-GPIO-TIO-HV-STATUS_) & 1) == polarity

  interrupt-polarity_ -> int:
    mux := (read-u8_ REG-GPIO-HV-MUX-CTRL_) & 0x10
    return mux == 0 ? 1 : 0

  /**
  Sets the polarity of the interrupt pin.

  If $active-high is true, the pin goes high when a measurement is ready.  The
    default configuration is active high.
  */
  set-interrupt-polarity --active-high/bool -> none:
    mux := (read-u8_ REG-GPIO-HV-MUX-CTRL_) & 0xEF
    write-u8_ REG-GPIO-HV-MUX-CTRL_ (mux | (active-high ? 0 : 0x10))

  /** Whether the interrupt pin is active high. */
  is-interrupt-active-high -> bool:
    return interrupt-polarity_ == 1

  // Measurements.

  /**
  Returns the most recent distance, in millimetres.

  Does not start a measurement or clear the interrupt.  See $read-range-mm.
  */
  read-distance-mm -> int:
    return read-u16_ REG-RESULT-FINAL-CROSSTALK-CORRECTED-RANGE-MM-SD0_

  /**
  Measures the distance to the target, in millimetres.

  If ranging is running (see $start-ranging), waits for the next measurement.
    Otherwise starts a single measurement and waits for it.  Clears the
    interrupt afterwards.  See $read-measurement for a version that also
    returns the status.
  */
  read-range-mm -> int:
    if not ranging_: start-oneshot
    wait-for_ "measurement": is-data-ready
    distance := read-distance-mm
    clear-interrupt
    return distance

  /**
  Measures the distance, like $read-range-mm, but returns more detail.

  Returns a $Vl53l1xMeasurement with the distance, a status that tells whether
    the distance can be trusted, and signal and ambient light levels.
  */
  read-measurement -> Vl53l1xMeasurement:
    if not ranging_: start-oneshot
    wait-for_ "measurement": is-data-ready
    block := read-bytes_ REG-RESULT-RANGE-STATUS_ 17
    clear-interrupt
    return Vl53l1xMeasurement.from-block_ block

  // Settings.

  /**
  Sets the distance mode to $mode, either $DISTANCE-SHORT or $DISTANCE-LONG.

  Re-applies the timing budget, which must be valid for the new mode.
  */
  set-distance-mode mode/int -> none:
    if mode != DISTANCE-SHORT and mode != DISTANCE-LONG: throw "OUT_OF_RANGE"
    budget := get-timing-budget-ms
    if mode == DISTANCE-SHORT:
      write-u8_ REG-PHASECAL-CONFIG-TIMEOUT-MACROP_ 0x14
      write-u8_ REG-RANGE-CONFIG-VCSEL-PERIOD-A_ 0x07
      write-u8_ REG-RANGE-CONFIG-VCSEL-PERIOD-B_ 0x05
      write-u8_ REG-RANGE-CONFIG-VALID-PHASE-HIGH_ 0x38
      write-u16_ REG-SD-CONFIG-WOI-SD0_ 0x0705
      write-u16_ REG-SD-CONFIG-INITIAL-PHASE-SD0_ 0x0606
    else:
      write-u8_ REG-PHASECAL-CONFIG-TIMEOUT-MACROP_ 0x0A
      write-u8_ REG-RANGE-CONFIG-VCSEL-PERIOD-A_ 0x0F
      write-u8_ REG-RANGE-CONFIG-VCSEL-PERIOD-B_ 0x0D
      write-u8_ REG-RANGE-CONFIG-VALID-PHASE-HIGH_ 0xB8
      write-u16_ REG-SD-CONFIG-WOI-SD0_ 0x0F0D
      write-u16_ REG-SD-CONFIG-INITIAL-PHASE-SD0_ 0x0E0E
    // The timing budget registers depend on the mode, so write them again.
    // If the budget was not one of the known values, it can't be restored.
    if budget != 0 and (timing-table_ mode).contains budget:
      set-timing-budget-ms budget

  /**
  Returns the distance mode: $DISTANCE-SHORT or $DISTANCE-LONG.
  Returns 0 if the sensor is in an unknown mode.
  */
  get-distance-mode -> int:
    value := read-u8_ REG-PHASECAL-CONFIG-TIMEOUT-MACROP_
    if value == 0x14: return DISTANCE-SHORT
    if value == 0x0A: return DISTANCE-LONG
    return 0

  timing-table_ mode/int -> Map:
    return mode == DISTANCE-SHORT ? TIMING-SHORT_ : TIMING-LONG_

  /**
  Sets the timing budget to $budget-ms milliseconds.

  This is the time the sensor spends on one measurement.  A longer budget gives
    a more accurate result.  The valid values are 15 (short distance mode only),
    20, 33, 50, 100, 200 and 500.  A longer budget also needs a longer
    inter-measurement period in continuous mode.

  Throws "OUT_OF_RANGE" for other values.
  */
  set-timing-budget-ms budget-ms/int -> none:
    mode := get-distance-mode
    if mode == 0: throw "VL53L1X: unknown distance mode"
    entry := (timing-table_ mode).get budget-ms
    if entry == null: throw "OUT_OF_RANGE"
    write-u16_ REG-RANGE-CONFIG-TIMEOUT-MACROP-A-HI_ entry[0]
    write-u16_ REG-RANGE-CONFIG-TIMEOUT-MACROP-B-HI_ entry[1]

  /**
  Returns the timing budget in milliseconds.
  Returns 0 if the timing registers hold a value that is not one of the
    supported budgets.
  */
  get-timing-budget-ms -> int:
    value := read-u16_ REG-RANGE-CONFIG-TIMEOUT-MACROP-A-HI_
    if value == 0x001D: return 15
    if value == 0x0051 or value == 0x001E: return 20
    if value == 0x00D6 or value == 0x0060: return 33
    if value == 0x01AE or value == 0x00AD: return 50
    if value == 0x02E1 or value == 0x01CC: return 100
    if value == 0x03E1 or value == 0x02D9: return 200
    if value == 0x0591 or value == 0x048F: return 500
    return 0

  /**
  Sets the time between measurements in continuous ranging to $period-ms.

  The period should be at least as long as the timing budget.
  */
  set-inter-measurement-ms period-ms/int -> none:
    if period-ms < 1: throw "OUT_OF_RANGE"
    clock-pll := (read-u16_ REG-RESULT-OSC-CALIBRATE-VAL_) & 0x3FF
    write-u32_ REG-SYSTEM-INTERMEASUREMENT-PERIOD_ (clock-pll * period-ms * 1.075).to-int

  /** Returns the time between measurements in continuous ranging, in milliseconds. */
  get-inter-measurement-ms -> int:
    raw := read-u32_ REG-SYSTEM-INTERMEASUREMENT-PERIOD_
    clock-pll := (read-u16_ REG-RESULT-OSC-CALIBRATE-VAL_) & 0x3FF
    if clock-pll == 0: return 0
    return (raw / (clock-pll * 1.065)).to-int

  /**
  Sets the region of interest to $width by $height SPADs (light detectors).

  Both must be between 4 and 16, the size of the full sensor array.  The
    region is centred on the SPAD $center, which is 199 for the middle of the
    array.  If either dimension is larger than 10, the region is always
    centred on 199.  Lower numbers give a narrower field of view.  The
    manufacturer's documentation has a map of the SPAD numbers.
  */
  set-roi --width/int --height/int --center/int=199 -> none:
    if width < 4 or width > 16 or height < 4 or height > 16: throw "OUT_OF_RANGE"
    if center < 0 or center > 255: throw "OUT_OF_RANGE"
    if width > 10 or height > 10: center = 199
    write-u8_ REG-ROI-CONFIG-USER-ROI-CENTRE-SPAD_ center
    write-u8_ REG-ROI-CONFIG-USER-ROI-REQUESTED-GLOBAL-XY-SIZE_ (((height - 1) << 4) | (width - 1))

  /** Returns the size of the region of interest as a list: width, then height. */
  get-roi-size -> List:
    value := read-u8_ REG-ROI-CONFIG-USER-ROI-REQUESTED-GLOBAL-XY-SIZE_
    return [(value & 0x0F) + 1, (value >> 4) + 1]

  /** Returns the centre SPAD of the region of interest. */
  get-roi-center -> int:
    return read-u8_ REG-ROI-CONFIG-USER-ROI-CENTRE-SPAD_

  /**
  Sets the minimum signal rate, in kcps (kilo counts per second).

  Measurements with a weaker returned signal get the $STATUS-SIGNAL-FAIL
    status.
  */
  set-signal-threshold-kcps threshold/int -> none:
    write-u16_ REG-RANGE-CONFIG-MIN-COUNT-RATE-RTN-LIMIT-MCPS_ (threshold >> 3)

  /** Returns the minimum signal rate, in kcps. */
  get-signal-threshold-kcps -> int:
    return ((read-u16_ REG-RANGE-CONFIG-MIN-COUNT-RATE-RTN-LIMIT-MCPS_) << 3) & 0xFFFF

  /**
  Sets the sigma (noise) threshold, in millimetres.

  Measurements with a higher sigma estimate get the $STATUS-SIGMA-FAIL status.
    The value must be below 16384.
  */
  set-sigma-threshold-mm threshold/int -> none:
    if threshold < 0 or threshold > (0xFFFF >> 2): throw "OUT_OF_RANGE"
    write-u16_ REG-RANGE-CONFIG-SIGMA-THRESH_ (threshold << 2)

  /** Returns the sigma threshold, in millimetres. */
  get-sigma-threshold-mm -> int:
    return (read-u16_ REG-RANGE-CONFIG-SIGMA-THRESH_) >> 2

  // Interrupt window.

  /**
  Sets the distance window that triggers the interrupt.

  The $window is one of $WINDOW-BELOW, $WINDOW-ABOVE, $WINDOW-OUT or
    $WINDOW-IN.  The interrupt triggers when the distance is below $low-mm,
    above $high-mm, outside both or inside both.  If $on-no-target is true, the
    interrupt also triggers when no target is found.  Use $is-data-ready or the
    interrupt pin to see it.
  */
  set-distance-threshold --low-mm/int --high-mm/int --window/int --on-no-target/bool=false -> none:
    if window < WINDOW-BELOW or window > WINDOW-IN: throw "OUT_OF_RANGE"
    value := (read-u8_ REG-SYSTEM-INTERRUPT-CONFIG-GPIO_) & 0x47
    value |= window & 0x07
    if on-no-target: value |= 0x40
    write-u8_ REG-SYSTEM-INTERRUPT-CONFIG-GPIO_ value
    write-u16_ REG-SYSTEM-THRESH-HIGH_ high-mm
    write-u16_ REG-SYSTEM-THRESH-LOW_ low-mm

  /** Returns the interrupt window type, one of $WINDOW-BELOW to $WINDOW-IN. */
  get-distance-threshold-window -> int:
    return (read-u8_ REG-SYSTEM-INTERRUPT-CONFIG-GPIO_) & 0x07

  /** Returns the low distance threshold, in millimetres. */
  get-distance-threshold-low-mm -> int:
    return read-u16_ REG-SYSTEM-THRESH-LOW_

  /** Returns the high distance threshold, in millimetres. */
  get-distance-threshold-high-mm -> int:
    return read-u16_ REG-SYSTEM-THRESH-HIGH_

  // Calibration.

  /**
  Sets the range offset, in millimetres, which is added to all measurements.
  The offset must be between -1024 and 1023.
  */
  set-offset-mm offset-mm/int -> none:
    if offset-mm < -1024 or offset-mm > 1023: throw "OUT_OF_RANGE"
    write-u16_ REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_ (offset-mm * 4)
    write-u16_ REG-MM-CONFIG-INNER-OFFSET-MM_ 0
    write-u16_ REG-MM-CONFIG-OUTER-OFFSET-MM_ 0

  /** Returns the range offset, in millimetres. */
  get-offset-mm -> int:
    // The register holds a signed 11-bit number in units of 1/4 mm, in bits
    // 12 to 2.
    value := ((read-u16_ REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_) >> 2) & 0x07FF
    if value >= 0x0400: value -= 0x0800
    return value

  /**
  Calibrates the range offset using a target at a known distance.

  Place a target (the manufacturer suggests a grey target with 17% reflectance)
    at $target-mm in front of the sensor, with nothing else in the field of
    view, and call this.  It clears the offsets, takes 50 measurements, and sets
    the offset to the difference between the target distance and the average.
    Returns the new offset in millimetres.  The offset is lost on power loss,
    so store it and set it again with $set-offset-mm.

  Stops any ranging that is running.
  */
  calibrate-offset --target-mm/int -> int:
    if ranging_: stop-ranging
    write-u16_ REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_ 0
    write-u16_ REG-MM-CONFIG-INNER-OFFSET-MM_ 0
    write-u16_ REG-MM-CONFIG-OUTER-OFFSET-MM_ 0
    start-ranging
    total := 0
    count := 0
    while count < 50:
      wait-for_ "measurement": is-data-ready
      total += read-distance-mm
      clear-interrupt
      count += 1
    stop-ranging
    offset := target-mm - (total / 50)
    write-u16_ REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_ (offset * 4)
    return offset

  /**
  Sets the crosstalk compensation, in cps (counts per second).

  Crosstalk is light that reaches the sensor from a cover glass in front of
    it.  A value of 0 turns the compensation off.
  */
  set-xtalk-cps xtalk/int -> none:
    if xtalk < 0 or xtalk > 0xFFFF: throw "OUT_OF_RANGE"
    write-u16_ REG-ALGO-CROSSTALK-COMPENSATION-X-PLANE-GRADIENT-KCPS_ 0
    write-u16_ REG-ALGO-CROSSTALK-COMPENSATION-Y-PLANE-GRADIENT-KCPS_ 0
    write-u16_ REG-ALGO-CROSSTALK-COMPENSATION-PLANE-OFFSET-KCPS_ ((xtalk << 9) / 1000)

  /** Returns the crosstalk compensation, in cps. */
  get-xtalk-cps -> int:
    value := read-u16_ REG-ALGO-CROSSTALK-COMPENSATION-PLANE-OFFSET-KCPS_
    return ((value * 1000) >> 9) & 0xFFFF

  /**
  Calibrates the crosstalk compensation using a target at a known distance.

  Place a target (the manufacturer suggests a grey target with 17% reflectance)
    at $target-mm in front of the sensor, behind the cover glass, and call
    this.  It takes 50 measurements and sets the crosstalk compensation.
    Returns the new value in cps.  The value is lost on power loss, so store
    it and set it again with $set-xtalk-cps.

  Stops any ranging that is running.
  */
  calibrate-xtalk --target-mm/int -> int:
    if ranging_: stop-ranging
    write-u16_ REG-ALGO-CROSSTALK-COMPENSATION-PLANE-OFFSET-KCPS_ 0
    start-ranging
    total-signal := 0
    total-distance := 0
    total-spads := 0
    count := 0
    while count < 50:
      wait-for_ "measurement": is-data-ready
      block := read-bytes_ REG-RESULT-RANGE-STATUS_ 17
      measurement := Vl53l1xMeasurement.from-block_ block
      total-signal += measurement.signal-rate-kcps
      total-distance += measurement.distance-mm
      total-spads += measurement.spad-count.to-int
      clear-interrupt
      count += 1
    stop-ranging
    average-signal := total-signal / 50.0
    average-distance := total-distance / 50.0
    average-spads := total-spads / 50.0
    if average-spads <= 0: throw "VL53L1X: no SPADs reported during calibration"
    xtalk := (512.0 * average-signal * (1.0 - (average-distance / target-mm)) / average-spads).to-int
    if xtalk < 0: xtalk = 0
    if xtalk > 0xFFFF: xtalk = 0xFFFF
    write-u16_ REG-ALGO-CROSSTALK-COMPENSATION-PLANE-OFFSET-KCPS_ xtalk
    return xtalk

  /**
  Runs a temperature calibration (a full VHV calibration) of the sensor.

  The manufacturer recommends this when the temperature has changed by more
    than 8 degrees Celsius since the last start-up or calibration.  Stops any
    ranging that is running.
  */
  update-temperature -> none:
    if ranging_: stop-ranging
    write-u8_ REG-VHV-CONFIG-TIMEOUT-MACROP-LOOP-BOUND_ 0x81  // Full VHV.
    write-u8_ 0x000B 0x92
    start-ranging
    wait-for_ "temperature update": is-data-ready
    clear-interrupt
    stop-ranging
    write-u8_ REG-VHV-CONFIG-TIMEOUT-MACROP-LOOP-BOUND_ 0x09  // Two bounds VHV.
    write-u8_ 0x000B 0  // Start VHV from the previous temperature.

/**
The result of a measurement of a $Vl53l1x.

The $distance-mm is only meaningful if $valid is true.
*/
class Vl53l1xMeasurement:
  /** The measured distance in millimetres. */
  distance-mm/int
  /** The measurement status, one of the Vl53l1x.STATUS-* constants. */
  status/int
  /** The status code as reported by the sensor, before it was interpreted. */
  raw-status/int
  /** The signal rate of the returned light, in kcps (kilo counts per second). */
  signal-rate-kcps/int
  /** The rate of ambient light that reached the sensor, in kcps. */
  ambient-rate-kcps/int
  /** The effective number of SPADs (light detectors) that were enabled. */
  spad-count/float

  constructor.from-block_ block/ByteArray:
    raw-status = (block[0]) & 0x1F
    status = Vl53l1xMeasurement.status-from-raw_ raw-status
    spad-count = (io.BIG-ENDIAN.uint16 block 3) / 256.0
    ambient-rate-kcps = (io.BIG-ENDIAN.uint16 block 7) * 8
    distance-mm = io.BIG-ENDIAN.uint16 block 13
    signal-rate-kcps = (io.BIG-ENDIAN.uint16 block 15) * 8

  static status-from-raw_ raw/int -> int:
    if raw == 9: return Vl53l1x.STATUS-VALID
    if raw == 6: return Vl53l1x.STATUS-SIGMA-FAIL
    if raw == 4: return Vl53l1x.STATUS-SIGNAL-FAIL
    if raw == 8: return Vl53l1x.STATUS-MIN-RANGE-CLIPPED
    if raw == 5: return Vl53l1x.STATUS-OUT-OF-BOUNDS
    if raw == 3: return Vl53l1x.STATUS-HARDWARE-FAIL
    if raw == 19: return Vl53l1x.STATUS-VALID-NO-WRAP-CHECK
    if raw == 7: return Vl53l1x.STATUS-WRAP-TARGET-FAIL
    if raw == 12: return Vl53l1x.STATUS-XTALK-SIGNAL-FAIL
    if raw == 18: return Vl53l1x.STATUS-SYNCHRONIZATION-INT
    if raw == 22: return Vl53l1x.STATUS-VALID-MERGED-PULSE
    if raw == 23: return Vl53l1x.STATUS-LACK-OF-SIGNAL
    if raw == 13: return Vl53l1x.STATUS-MIN-RANGE-FAIL
    return Vl53l1x.STATUS-NO-UPDATE

  /** Whether the distance can be trusted: the status is $Vl53l1x.STATUS-VALID. */
  valid -> bool:
    return status == Vl53l1x.STATUS-VALID

  /** The signal rate per SPAD, in kcps, or 0 if no SPADs were reported. */
  signal-per-spad-kcps -> float:
    return spad-count > 0 ? signal-rate-kcps / spad-count : 0.0

  /** The ambient light rate per SPAD, in kcps, or 0 if no SPADs were reported. */
  ambient-per-spad-kcps -> float:
    return spad-count > 0 ? ambient-rate-kcps / spad-count : 0.0

  /** A short description of the $status. */
  status-name -> string:
    if status == Vl53l1x.STATUS-VALID: return "valid"
    if status == Vl53l1x.STATUS-SIGMA-FAIL: return "sigma fail"
    if status == Vl53l1x.STATUS-SIGNAL-FAIL: return "signal fail"
    if status == Vl53l1x.STATUS-MIN-RANGE-CLIPPED: return "valid, min range clipped"
    if status == Vl53l1x.STATUS-OUT-OF-BOUNDS: return "out of bounds"
    if status == Vl53l1x.STATUS-HARDWARE-FAIL: return "hardware fail"
    if status == Vl53l1x.STATUS-VALID-NO-WRAP-CHECK: return "valid, no wrap check"
    if status == Vl53l1x.STATUS-WRAP-TARGET-FAIL: return "wrap target fail"
    if status == Vl53l1x.STATUS-PROCESSING-FAIL: return "processing fail"
    if status == Vl53l1x.STATUS-XTALK-SIGNAL-FAIL: return "xtalk signal fail"
    if status == Vl53l1x.STATUS-SYNCHRONIZATION-INT: return "synchronization interrupt"
    if status == Vl53l1x.STATUS-VALID-MERGED-PULSE: return "valid, merged pulse"
    if status == Vl53l1x.STATUS-LACK-OF-SIGNAL: return "lack of signal"
    if status == Vl53l1x.STATUS-MIN-RANGE-FAIL: return "min range fail"
    if status == Vl53l1x.STATUS-INVALID: return "invalid"
    return "no update"

  stringify -> string:
    return "$distance-mm mm ($status-name)"
