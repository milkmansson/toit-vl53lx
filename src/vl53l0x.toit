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
Driver for the VL53L0X time-of-flight distance sensor.

The VL53L0X measures the distance to a target using a laser pulse and returns
  it in millimetres.  Its register map is not published, so this driver is built
  from the register sequences used by several other open-source libraries.  See
  the package README for the sources.

The constructor checks the model ID, performs the initialization sequence
  (including the reference calibrations) and leaves the sensor idle and ready
  for single-shot measurements.  It throws if the sensor does not answer or
  reports an unexpected model ID.

Single-shot measurements are the simplest way to use the sensor:
```
bus := i2c.Bus --sda=(gpio.Pin 21) --scl=(gpio.Pin 22)
sensor := Vl53l0x (bus.device Vl53l0x.I2C-ADDRESS)
print "$sensor.read-range-mm mm"
```

For repeated measurements call $start-continuous once and then read with
  $read-range-mm or $read-measurement.

A range of 8190 or more usually means that no target was found.  Use
  $read-measurement and check $Vl53l0xMeasurement.status for a better answer.

# Reliability
Methods that talk to the sensor throw if the I2C transaction fails.  Methods
  that wait for the sensor throw "VL53L0X: timeout waiting for ..." when the
  sensor does not answer within the timeout given to the constructor.
*/
class Vl53l0x:
  /** The default I2C address of the sensor (7-bit). */
  static I2C-ADDRESS ::= 0x29
  /** The value that a VL53L0X reports in its model ID register. */
  static MODEL-ID ::= 0xEE

  /** The default ranging profile. */
  static PROFILE-DEFAULT ::= 0
  /**
  Ranging profile for a longer range, at the cost of more noise and a higher
    chance of false readings.  Works best in the dark and with reflective
    targets.
  */
  static PROFILE-LONG-RANGE ::= 1
  /** Ranging profile with a 20 ms timing budget: faster but less accurate. */
  static PROFILE-HIGH-SPEED ::= 2
  /** Ranging profile with a 200 ms timing budget: slower but more accurate. */
  static PROFILE-HIGH-ACCURACY ::= 3

  /** Selects the pre-range VCSEL pulse period. */
  static VCSEL-PRE-RANGE ::= 0
  /** Selects the final-range VCSEL pulse period. */
  static VCSEL-FINAL-RANGE ::= 1

  /** The interrupt pin is not driven. */
  static GPIO-OFF ::= 0
  /** The interrupt triggers when the range falls below the low threshold. */
  static GPIO-LEVEL-LOW ::= 1
  /** The interrupt triggers when the range goes above the high threshold. */
  static GPIO-LEVEL-HIGH ::= 2
  /** The interrupt triggers when the range is outside the thresholds. */
  static GPIO-OUT-OF-WINDOW ::= 3
  /** The interrupt triggers when a new measurement is ready. */
  static GPIO-NEW-SAMPLE-READY ::= 4

  /** Measurement status: the range is valid. */
  static STATUS-VALID ::= 0
  /**
  Measurement status: the sigma limit check failed.
  This driver does not evaluate the sigma limit, so it never reports this.
  */
  static STATUS-SIGMA-FAIL ::= 1
  /** Measurement status: the returned signal was too weak. */
  static STATUS-SIGNAL-FAIL ::= 2
  /** Measurement status: the target is too close to measure. */
  static STATUS-MIN-RANGE-FAIL ::= 3
  /** Measurement status: the phase was out of limits, for example a wrap-around. */
  static STATUS-PHASE-FAIL ::= 4
  /** Measurement status: a hardware failure was reported. */
  static STATUS-HARDWARE-FAIL ::= 5
  /** Measurement status: no valid result or no update. */
  static STATUS-NO-UPDATE ::= 255

  // Register addresses.
  static REG-SYSRANGE-START_ ::= 0x00
  static REG-SYSTEM-SEQUENCE-CONFIG_ ::= 0x01
  static REG-SYSTEM-INTERMEASUREMENT-PERIOD_ ::= 0x04
  static REG-SYSTEM-INTERRUPT-CONFIG-GPIO_ ::= 0x0A
  static REG-SYSTEM-INTERRUPT-CLEAR_ ::= 0x0B
  static REG-SYSTEM-THRESH-HIGH_ ::= 0x0C
  static REG-SYSTEM-THRESH-LOW_ ::= 0x0E
  static REG-RESULT-INTERRUPT-STATUS_ ::= 0x13
  static REG-RESULT-RANGE-STATUS_ ::= 0x14
  static REG-CROSSTALK-COMPENSATION-PEAK-RATE-MCPS_ ::= 0x20
  static REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_ ::= 0x28
  static REG-FINAL-RANGE-CONFIG-VALID-PHASE-LOW_ ::= 0x47
  static REG-FINAL-RANGE-CONFIG-VALID-PHASE-HIGH_ ::= 0x48
  static REG-FINAL-RANGE-CONFIG-MIN-COUNT-RATE-RTN-LIMIT_ ::= 0x44
  static REG-MSRC-CONFIG-TIMEOUT-MACROP_ ::= 0x46
  static REG-PRE-RANGE-CONFIG-VCSEL-PERIOD_ ::= 0x50
  static REG-PRE-RANGE-CONFIG-TIMEOUT-MACROP-HI_ ::= 0x51
  static REG-PRE-RANGE-CONFIG-VALID-PHASE-LOW_ ::= 0x56
  static REG-PRE-RANGE-CONFIG-VALID-PHASE-HIGH_ ::= 0x57
  static REG-MSRC-CONFIG-CONTROL_ ::= 0x60
  static REG-FINAL-RANGE-CONFIG-VCSEL-PERIOD_ ::= 0x70
  static REG-FINAL-RANGE-CONFIG-TIMEOUT-MACROP-HI_ ::= 0x71
  static REG-GPIO-HV-MUX-ACTIVE-HIGH_ ::= 0x84
  static REG-VHV-CONFIG-PAD-SCL-SDA-EXTSUP-HV_ ::= 0x89
  static REG-I2C-SLAVE-DEVICE-ADDRESS_ ::= 0x8A
  static REG-SOFT-RESET_ ::= 0xBF
  static REG-IDENTIFICATION-MODEL-ID_ ::= 0xC0
  static REG-IDENTIFICATION-REVISION-ID_ ::= 0xC2
  static REG-OSC-CALIBRATE-VAL_ ::= 0xF8
  static REG-GLOBAL-CONFIG-VCSEL-WIDTH_ ::= 0x32
  static REG-GLOBAL-CONFIG-SPAD-ENABLES-REF-0_ ::= 0xB0
  static REG-GLOBAL-CONFIG-REF-EN-START-SELECT_ ::= 0xB6
  static REG-DYNAMIC-SPAD-NUM-REQUESTED-REF-SPAD_ ::= 0x4E
  static REG-DYNAMIC-SPAD-REF-EN-START-OFFSET_ ::= 0x4F
  static REG-ALGO-PHASECAL-LIM_ ::= 0x30  // On page 1 (see the page register).
  static REG-ALGO-PHASECAL-CONFIG-TIMEOUT_ ::= 0x30  // On page 0.
  // Register 0xFF selects between pages of registers.  The same address can
  // mean different things on different pages.
  static REG-PAGE-SELECT_ ::= 0xFF

  // The default tuning settings, as address/value pairs, in the order they must
  // be written.  The order and the repeated page-select writes (0xFF) matter.
  // These values are not documented by the manufacturer.
  static TUNING-SETTINGS_ ::= #[
    0xFF, 0x01, 0x00, 0x00, 0xFF, 0x00, 0x09, 0x00,
    0x10, 0x00, 0x11, 0x00, 0x24, 0x01, 0x25, 0xFF,
    0x75, 0x00, 0xFF, 0x01, 0x4E, 0x2C, 0x48, 0x00,
    0x30, 0x20, 0xFF, 0x00, 0x30, 0x09, 0x54, 0x00,
    0x31, 0x04, 0x32, 0x03, 0x40, 0x83, 0x46, 0x25,
    0x60, 0x00, 0x27, 0x00, 0x50, 0x06, 0x51, 0x00,
    0x52, 0x96, 0x56, 0x08, 0x57, 0x30, 0x61, 0x00,
    0x62, 0x00, 0x64, 0x00, 0x65, 0x00, 0x66, 0xA0,
    0xFF, 0x01, 0x22, 0x32, 0x47, 0x14, 0x49, 0xFF,
    0x4A, 0x00, 0xFF, 0x00, 0x7A, 0x0A, 0x7B, 0x00,
    0x78, 0x21, 0xFF, 0x01, 0x23, 0x34, 0x42, 0x00,
    0x44, 0xFF, 0x45, 0x26, 0x46, 0x05, 0x40, 0x40,
    0x0E, 0x06, 0x20, 0x1A, 0x43, 0x40, 0xFF, 0x00,
    0x34, 0x03, 0x35, 0x44, 0xFF, 0x01, 0x31, 0x04,
    0x4B, 0x09, 0x4C, 0x05, 0x4D, 0x04, 0xFF, 0x00,
    0x44, 0x00, 0x45, 0x20, 0x47, 0x08, 0x48, 0x28,
    0x67, 0x00, 0x70, 0x04, 0x71, 0x01, 0x72, 0xFE,
    0x76, 0x00, 0x77, 0x00, 0xFF, 0x01, 0x0D, 0x01,
    0xFF, 0x00, 0x80, 0x01, 0x01, 0xF8, 0xFF, 0x01,
    0x8E, 0x01, 0x00, 0x01, 0xFF, 0x00, 0x80, 0x00,
  ]

  reg_/serial.Registers
  logger_/log.Logger
  timeout-ms_/int
  io-2v8_/bool
  stop-variable_/int := 0
  continuous_/bool := false
  measurement-timing-budget-us_/int := 0
  default-budget-us_/int := 0
  reference-spad-count_/int := 0
  reference-spad-aperture_/bool := false

  /**
  Constructs a driver for the VL53L0X on the given $device and initializes it.

  The $device is typically an I2C device at address $I2C-ADDRESS.

  If $io-2v8 is true (the default), the sensor's I2C and interrupt pins are
    configured for 2.8 V logic.  Many breakout boards with a voltage regulator
    expect this.  Set it to false for a 1.8 V bus.

  The $profile selects a set of ranging settings.  It is one of
    $PROFILE-DEFAULT, $PROFILE-LONG-RANGE, $PROFILE-HIGH-SPEED or
    $PROFILE-HIGH-ACCURACY.

  The $timeout-ms is the longest time to wait for the sensor in any operation.
  */
  constructor device/serial.Device
      --logger/log.Logger=log.default
      --io-2v8/bool=true
      --profile/int=PROFILE-DEFAULT
      --timeout-ms/int=500:
    reg_ = device.registers
    logger_ = logger.with-name "vl53l0x"
    timeout-ms_ = timeout-ms
    io-2v8_ = io-2v8
    initialize_ io-2v8
    if profile != PROFILE-DEFAULT: set-profile profile

  // Low-level register access.

  read-u8_ register/int -> int:
    return reg_.read-u8 register

  write-u8_ register/int value/int -> none:
    reg_.write-u8 register value

  read-u16_ register/int -> int:
    return reg_.read-u16-be register

  write-u16_ register/int value/int -> none:
    reg_.write-u16-be register value

  read-u32_ register/int -> int:
    return reg_.read-u32-be register

  write-u32_ register/int value/int -> none:
    bytes := ByteArray 4
    io.BIG-ENDIAN.put-uint32 bytes 0 value
    reg_.write-bytes register bytes

  /** Waits until the $condition block returns true. */
  wait-for_ what/string [condition] -> none:
    deadline := Time.monotonic-us + (timeout-ms_ * 1000)
    while not condition.call:
      if Time.monotonic-us > deadline: throw "VL53L0X: timeout waiting for $what"
      sleep --ms=1

  /** Selects a register page. */
  select-page_ page/int -> none:
    write-u8_ REG-PAGE-SELECT_ page

  /**
  Writes the sequence that makes the sensor use the saved stop variable.
  It is needed before every measurement is started.
  */
  restore-stop-variable_ -> none:
    write-u8_ 0x80 0x01
    write-u8_ 0xFF 0x01
    write-u8_ 0x00 0x00
    write-u8_ 0x91 stop-variable_
    write-u8_ 0x00 0x01
    write-u8_ 0xFF 0x00
    write-u8_ 0x80 0x00

  // Initialization.

  initialize_ io-2v8/bool -> none:
    model := read-u8_ REG-IDENTIFICATION-MODEL-ID_
    if model != MODEL-ID:
      throw "VL53L0X: unexpected model ID 0x$(%02x model) (expected 0x$(%02x MODEL-ID))"

    // The sensor uses 1.8 V I/O by default.
    if io-2v8:
      write-u8_ REG-VHV-CONFIG-PAD-SCL-SDA-EXTSUP-HV_
          ((read-u8_ REG-VHV-CONFIG-PAD-SCL-SDA-EXTSUP-HV_) | 0x01)

    // Set I2C standard mode.
    write-u8_ 0x88 0x00

    // Read the stop variable.  It is needed to start measurements.
    write-u8_ 0x80 0x01
    write-u8_ 0xFF 0x01
    write-u8_ 0x00 0x00
    stop-variable_ = read-u8_ 0x91
    write-u8_ 0x00 0x01
    write-u8_ 0xFF 0x00
    write-u8_ 0x80 0x00

    // Disable the SIGNAL_RATE_MSRC (bit 1) and SIGNAL_RATE_PRE_RANGE (bit 4)
    // limit checks.
    write-u8_ REG-MSRC-CONFIG-CONTROL_ ((read-u8_ REG-MSRC-CONFIG-CONTROL_) | 0x12)

    // Set the final-range signal rate limit to 0.25 MCPS.
    set-signal-rate-limit 0.25

    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ 0xFF

    // Reference SPADs.  This takes the count and type from the factory data
    // and does not run the reference SPAD calibration.  That should work well
    // enough unless a cover glass has been added over the sensor.
    spad-info := read-spad-info_
    spad-count := spad-info[0]
    spad-aperture := spad-info[1]
    reference-spad-count_ = spad-count
    reference-spad-aperture_ = spad-aperture
    spad-map := reg_.read-bytes REG-GLOBAL-CONFIG-SPAD-ENABLES-REF-0_ 6

    write-u8_ 0xFF 0x01
    write-u8_ REG-DYNAMIC-SPAD-REF-EN-START-OFFSET_ 0x00
    write-u8_ REG-DYNAMIC-SPAD-NUM-REQUESTED-REF-SPAD_ 0x2C
    write-u8_ 0xFF 0x00
    write-u8_ REG-GLOBAL-CONFIG-REF-EN-START-SELECT_ 0xB4

    first-spad-to-enable := spad-aperture ? 12 : 0  // 12 is the first aperture SPAD.
    spads-enabled := 0
    48.repeat: | i |
      if i < first-spad-to-enable or spads-enabled == spad-count:
        spad-map[i / 8] &= ~(1 << (i % 8))
      else if ((spad-map[i / 8] >> (i % 8)) & 1) == 1:
        spads-enabled += 1
    reg_.write-bytes REG-GLOBAL-CONFIG-SPAD-ENABLES-REF-0_ spad-map

    // Load the default tuning settings.
    i := 0
    while i < TUNING-SETTINGS_.size:
      write-u8_ TUNING-SETTINGS_[i] TUNING-SETTINGS_[i + 1]
      i += 2

    // Set the interrupt to "new sample ready", active low.
    configure-interrupt GPIO-NEW-SAMPLE-READY --no-active-high

    measurement-timing-budget-us_ = get-measurement-timing-budget

    // Disable MSRC and TCC by default.
    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ 0xE8

    // Recalculate the timing budget.
    set-measurement-timing-budget measurement-timing-budget-us_
    default-budget-us_ = measurement-timing-budget-us_

    // Reference calibrations: VHV, then phase.
    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ 0x01
    perform-single-ref-calibration_ 0x40
    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ 0x02
    perform-single-ref-calibration_ 0x00

    // Restore the sequence config.
    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ 0xE8

  /**
  Reads the reference SPAD count and type from the factory data.
  Returns a list with the count and a bool that is true for aperture SPADs.
  */
  read-spad-info_ -> List:
    write-u8_ 0x80 0x01
    write-u8_ 0xFF 0x01
    write-u8_ 0x00 0x00

    write-u8_ 0xFF 0x06
    write-u8_ 0x83 ((read-u8_ 0x83) | 0x04)
    write-u8_ 0xFF 0x07
    write-u8_ 0x81 0x01

    write-u8_ 0x80 0x01

    write-u8_ 0x94 0x6B
    write-u8_ 0x83 0x00
    wait-for_ "SPAD info": (read-u8_ 0x83) != 0x00
    write-u8_ 0x83 0x01
    info := read-u8_ 0x92

    write-u8_ 0x81 0x00
    write-u8_ 0xFF 0x06
    write-u8_ 0x83 ((read-u8_ 0x83) & ~0x04)
    write-u8_ 0xFF 0x01
    write-u8_ 0x00 0x01

    write-u8_ 0xFF 0x00
    write-u8_ 0x80 0x00

    return [info & 0x7F, ((info >> 7) & 1) == 1]

  perform-single-ref-calibration_ vhv-init-byte/int -> none:
    write-u8_ REG-SYSRANGE-START_ (0x01 | vhv-init-byte)
    wait-for_ "reference calibration":
      ((read-u8_ REG-RESULT-INTERRUPT-STATUS_) & 0x07) != 0
    write-u8_ REG-SYSTEM-INTERRUPT-CLEAR_ 0x01
    write-u8_ REG-SYSRANGE-START_ 0x00

  // Identification.

  /** Returns the model ID register. A VL53L0X reports $MODEL-ID. */
  model-id -> int:
    return read-u8_ REG-IDENTIFICATION-MODEL-ID_

  /** Returns the revision ID register. */
  revision-id -> int:
    return read-u8_ REG-IDENTIFICATION-REVISION-ID_

  /** The number of reference SPADs found in the factory data during setup. */
  reference-spad-count -> int:
    return reference-spad-count_

  /** Whether the reference SPADs found during setup are aperture SPADs. */
  reference-spad-aperture -> bool:
    return reference-spad-aperture_

  /**
  Changes the I2C address of the sensor to $new-address (7-bit).

  The change is lost when the sensor loses power or is reset with its XSHUT
    pin.  Afterwards the sensor answers on the new address, so the caller must
    open a new I2C device for it.  This object keeps using the old address.
  */
  set-address new-address/int -> none:
    if new-address < 0x08 or new-address > 0x77: throw "OUT_OF_RANGE"
    write-u8_ REG-I2C-SLAVE-DEVICE-ADDRESS_ (new-address & 0x7F)

  /**
  Resets the sensor with its soft reset register and initializes it again.

  All settings, including calibration values written by the caller, are lost.
  */
  reset -> none:
    if continuous_: stop-continuous
    write-u8_ REG-SOFT-RESET_ 0x00
    sleep --ms=2
    write-u8_ REG-SOFT-RESET_ 0x01
    sleep --ms=5
    initialize_ io-2v8_

  /** Stops continuous measurements, if they are running. */
  close -> none:
    if continuous_: stop-continuous

  // Settings.

  /**
  Sets the return signal rate limit, in MCPS (million counts per second).

  The sensor needs at least this much returned signal to report a valid
    reading.  A lower limit increases the potential range, but also the chance
    of an inaccurate reading caused by reflections from other objects.  The
    default is 0.25.

  The value is stored with 7 fractional bits, so it is rounded down to a
    multiple of 1/128.  It must be between 0 and 511.99.
  */
  set-signal-rate-limit limit-mcps/num -> none:
    if limit-mcps < 0 or limit-mcps > 511.99: throw "OUT_OF_RANGE"
    write-u16_ REG-FINAL-RANGE-CONFIG-MIN-COUNT-RATE-RTN-LIMIT_
        (limit-mcps * 128.0).to-int

  /** Returns the return signal rate limit, in MCPS. */
  get-signal-rate-limit -> float:
    return (read-u16_ REG-FINAL-RANGE-CONFIG-MIN-COUNT-RATE-RTN-LIMIT_) / 128.0

  /**
  Sets the measurement timing budget to $budget-us microseconds.

  This is the time allowed for one measurement.  A longer budget gives more
    accurate measurements: multiplying it by N reduces the standard deviation
    of the result by a factor of the square root of N.  The default is about
    30 ms and the minimum is about 20 ms.

  Throws "OUT_OF_RANGE" if the budget is too short for the enabled
    measurement steps.
  */
  set-measurement-timing-budget budget-us/int -> none:
    start-overhead := 1910
    end-overhead := 960
    msrc-overhead := 660
    tcc-overhead := 590
    dss-overhead := 690
    pre-range-overhead := 660
    final-range-overhead := 550

    used-budget-us := start-overhead + end-overhead

    steps := SequenceSteps_ (read-u8_ REG-SYSTEM-SEQUENCE-CONFIG_)
    timeouts := get-step-timeouts_ steps

    if steps.tcc:
      used-budget-us += timeouts.msrc-us + tcc-overhead
    if steps.dss:
      used-budget-us += 2 * (timeouts.msrc-us + dss-overhead)
    else if steps.msrc:
      used-budget-us += timeouts.msrc-us + msrc-overhead
    if steps.pre-range:
      used-budget-us += timeouts.pre-range-us + pre-range-overhead

    if steps.final-range:
      used-budget-us += final-range-overhead

      if used-budget-us > budget-us: throw "OUT_OF_RANGE"

      final-range-timeout-us := budget-us - used-budget-us

      // The final-range timeout includes the pre-range timeout.  Both have to
      // be expressed in macro periods, because they use different VCSEL
      // periods.
      final-range-timeout-mclks := timeout-us-to-mclks_
          final-range-timeout-us
          timeouts.final-range-vcsel
      if steps.pre-range:
        final-range-timeout-mclks += timeouts.pre-range-mclks

      write-u16_ REG-FINAL-RANGE-CONFIG-TIMEOUT-MACROP-HI_
          (encode-timeout_ final-range-timeout-mclks)

      measurement-timing-budget-us_ = budget-us

  /** Returns the measurement timing budget, in microseconds. */
  get-measurement-timing-budget -> int:
    start-overhead := 1910
    end-overhead := 960
    msrc-overhead := 660
    tcc-overhead := 590
    dss-overhead := 690
    pre-range-overhead := 660
    final-range-overhead := 550

    budget-us := start-overhead + end-overhead

    steps := SequenceSteps_ (read-u8_ REG-SYSTEM-SEQUENCE-CONFIG_)
    timeouts := get-step-timeouts_ steps

    if steps.tcc:
      budget-us += timeouts.msrc-us + tcc-overhead
    if steps.dss:
      budget-us += 2 * (timeouts.msrc-us + dss-overhead)
    else if steps.msrc:
      budget-us += timeouts.msrc-us + msrc-overhead
    if steps.pre-range:
      budget-us += timeouts.pre-range-us + pre-range-overhead
    if steps.final-range:
      budget-us += timeouts.final-range-us + final-range-overhead

    measurement-timing-budget-us_ = budget-us
    return budget-us

  /**
  Sets the VCSEL (laser) pulse period for the given $type to $period-pclks.

  The $type is $VCSEL-PRE-RANGE or $VCSEL-FINAL-RANGE.  Longer periods
    increase the potential range of the sensor.  The valid values are even
    numbers: 12 to 18 for the pre-range period (default 14) and 8 to 14 for
    the final-range period (default 10).

  Throws "OUT_OF_RANGE" for other values.  Changing the period runs a phase
    calibration, which takes a few milliseconds.
  */
  set-vcsel-pulse-period type/int period-pclks/int -> none:
    vcsel-period-reg := encode-vcsel-period_ period-pclks

    steps := SequenceSteps_ (read-u8_ REG-SYSTEM-SEQUENCE-CONFIG_)
    timeouts := get-step-timeouts_ steps

    // When a VCSEL period changes, the matching timeout must be read using the
    // old period and written back using the new one.
    if type == VCSEL-PRE-RANGE:
      if period-pclks == 12:
        write-u8_ REG-PRE-RANGE-CONFIG-VALID-PHASE-HIGH_ 0x18
      else if period-pclks == 14:
        write-u8_ REG-PRE-RANGE-CONFIG-VALID-PHASE-HIGH_ 0x30
      else if period-pclks == 16:
        write-u8_ REG-PRE-RANGE-CONFIG-VALID-PHASE-HIGH_ 0x40
      else if period-pclks == 18:
        write-u8_ REG-PRE-RANGE-CONFIG-VALID-PHASE-HIGH_ 0x50
      else:
        throw "OUT_OF_RANGE"
      write-u8_ REG-PRE-RANGE-CONFIG-VALID-PHASE-LOW_ 0x08

      write-u8_ REG-PRE-RANGE-CONFIG-VCSEL-PERIOD_ vcsel-period-reg

      new-pre-range-timeout-mclks := timeout-us-to-mclks_ timeouts.pre-range-us period-pclks
      write-u16_ REG-PRE-RANGE-CONFIG-TIMEOUT-MACROP-HI_
          (encode-timeout_ new-pre-range-timeout-mclks)

      new-msrc-timeout-mclks := timeout-us-to-mclks_ timeouts.msrc-us period-pclks
      msrc-register-value := new-msrc-timeout-mclks > 256 ? 255 : (new-msrc-timeout-mclks - 1)
      write-u8_ REG-MSRC-CONFIG-TIMEOUT-MACROP_ msrc-register-value
    else if type == VCSEL-FINAL-RANGE:
      if period-pclks == 8:
        set-final-range-phase_ 0x10 0x02 0x0C 0x30
      else if period-pclks == 10:
        set-final-range-phase_ 0x28 0x03 0x09 0x20
      else if period-pclks == 12:
        set-final-range-phase_ 0x38 0x03 0x08 0x20
      else if period-pclks == 14:
        set-final-range-phase_ 0x48 0x03 0x07 0x20
      else:
        throw "OUT_OF_RANGE"

      write-u8_ REG-FINAL-RANGE-CONFIG-VCSEL-PERIOD_ vcsel-period-reg

      new-final-range-timeout-mclks := timeout-us-to-mclks_ timeouts.final-range-us period-pclks
      if steps.pre-range:
        new-final-range-timeout-mclks += timeouts.pre-range-mclks
      write-u16_ REG-FINAL-RANGE-CONFIG-TIMEOUT-MACROP-HI_
          (encode-timeout_ new-final-range-timeout-mclks)
    else:
      throw "OUT_OF_RANGE"

    // Re-apply the timing budget.
    set-measurement-timing-budget measurement-timing-budget-us_

    // Perform the phase calibration, which is needed after changing a VCSEL
    // period.
    sequence-config := read-u8_ REG-SYSTEM-SEQUENCE-CONFIG_
    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ 0x02
    perform-single-ref-calibration_ 0x00
    write-u8_ REG-SYSTEM-SEQUENCE-CONFIG_ sequence-config

  set-final-range-phase_ phase-high/int vcsel-width/int phasecal-timeout/int phasecal-limit/int -> none:
    write-u8_ REG-FINAL-RANGE-CONFIG-VALID-PHASE-HIGH_ phase-high
    write-u8_ REG-FINAL-RANGE-CONFIG-VALID-PHASE-LOW_ 0x08
    write-u8_ REG-GLOBAL-CONFIG-VCSEL-WIDTH_ vcsel-width
    write-u8_ REG-ALGO-PHASECAL-CONFIG-TIMEOUT_ phasecal-timeout
    select-page_ 0x01
    write-u8_ REG-ALGO-PHASECAL-LIM_ phasecal-limit
    select-page_ 0x00

  /**
  Returns the VCSEL pulse period for the given $type, in PCLKs.
  The $type is $VCSEL-PRE-RANGE or $VCSEL-FINAL-RANGE.
  */
  get-vcsel-pulse-period type/int -> int:
    if type == VCSEL-PRE-RANGE:
      return decode-vcsel-period_ (read-u8_ REG-PRE-RANGE-CONFIG-VCSEL-PERIOD_)
    if type == VCSEL-FINAL-RANGE:
      return decode-vcsel-period_ (read-u8_ REG-FINAL-RANGE-CONFIG-VCSEL-PERIOD_)
    throw "OUT_OF_RANGE"

  /**
  Applies one of the ranging profiles.

  The $profile is one of $PROFILE-DEFAULT, $PROFILE-LONG-RANGE,
    $PROFILE-HIGH-SPEED or $PROFILE-HIGH-ACCURACY.  The profile first restores
    the default signal rate limit, VCSEL periods and timing budget and then
    changes what it needs to.  Stops continuous mode, if it is running.
  */
  set-profile profile/int -> none:
    if profile < PROFILE-DEFAULT or profile > PROFILE-HIGH-ACCURACY: throw "OUT_OF_RANGE"
    was-continuous := continuous_
    if continuous_: stop-continuous
    set-signal-rate-limit 0.25
    if (get-vcsel-pulse-period VCSEL-PRE-RANGE) != 14:
      set-vcsel-pulse-period VCSEL-PRE-RANGE 14
    if (get-vcsel-pulse-period VCSEL-FINAL-RANGE) != 10:
      set-vcsel-pulse-period VCSEL-FINAL-RANGE 10
    set-measurement-timing-budget default-budget-us_
    if profile == PROFILE-LONG-RANGE:
      set-signal-rate-limit 0.1
      set-vcsel-pulse-period VCSEL-PRE-RANGE 18
      set-vcsel-pulse-period VCSEL-FINAL-RANGE 14
    else if profile == PROFILE-HIGH-SPEED:
      set-measurement-timing-budget 20_000
    else if profile == PROFILE-HIGH-ACCURACY:
      set-measurement-timing-budget 200_000
    if was-continuous: logger_.warn "continuous mode was stopped by set-profile"

  // Measurements.

  /**
  Measures the distance to the target, in millimetres.

  If continuous mode is running (see $start-continuous), waits for the next
    measurement.  Otherwise starts a single-shot measurement and waits for it.
  See $read-measurement for a version that also returns the status.
  */
  read-range-mm -> int:
    if not continuous_: start-single_
    wait-for-data_
    range := read-u16_ (REG-RESULT-RANGE-STATUS_ + 10)
    clear-interrupt
    return range

  /**
  Measures the distance, like $read-range-mm, but returns more detail.

  Returns a $Vl53l0xMeasurement with the distance, a status that tells whether
    the distance can be trusted, and signal and ambient light levels.
  */
  read-measurement -> Vl53l0xMeasurement:
    if not continuous_: start-single_
    wait-for-data_
    block := reg_.read-bytes REG-RESULT-RANGE-STATUS_ 12
    clear-interrupt
    return Vl53l0xMeasurement.from-block_ block

  start-single_ -> none:
    restore-stop-variable_
    write-u8_ REG-SYSRANGE-START_ 0x01
    wait-for_ "measurement start": ((read-u8_ REG-SYSRANGE-START_) & 0x01) == 0

  wait-for-data_ -> none:
    wait-for_ "measurement": is-data-ready

  /** Whether a new measurement is ready to be read. */
  is-data-ready -> bool:
    return ((read-u8_ REG-RESULT-INTERRUPT-STATUS_) & 0x07) != 0

  /** Clears the interrupt flag, so that the sensor can signal a new measurement. */
  clear-interrupt -> none:
    write-u8_ REG-SYSTEM-INTERRUPT-CLEAR_ 0x01

  /**
  Starts continuous measurements.

  If $period-ms is 0 (the default), the sensor measures back to back, as often
    as it can.  Otherwise it takes a measurement every $period-ms milliseconds.
    The period should be longer than the timing budget.

  Read the results with $read-range-mm or $read-measurement.
  */
  start-continuous --period-ms/int=0 -> none:
    restore-stop-variable_
    if period-ms != 0:
      period := period-ms
      osc-calibrate-val := read-u16_ REG-OSC-CALIBRATE-VAL_
      if osc-calibrate-val != 0: period *= osc-calibrate-val
      write-u32_ REG-SYSTEM-INTERMEASUREMENT-PERIOD_ period
      write-u8_ REG-SYSRANGE-START_ 0x04  // Continuous timed mode.
    else:
      write-u8_ REG-SYSRANGE-START_ 0x02  // Continuous back-to-back mode.
    continuous_ = true

  /** Stops continuous measurements. */
  stop-continuous -> none:
    write-u8_ REG-SYSRANGE-START_ 0x01
    write-u8_ 0xFF 0x01
    write-u8_ 0x00 0x00
    write-u8_ 0x91 0x00
    write-u8_ 0x00 0x01
    write-u8_ 0xFF 0x00
    continuous_ = false

  // Interrupt pin.

  /**
  Configures the interrupt pin to signal the given $function.

  The $function is one of $GPIO-OFF, $GPIO-LEVEL-LOW, $GPIO-LEVEL-HIGH,
    $GPIO-OUT-OF-WINDOW or $GPIO-NEW-SAMPLE-READY.  The threshold functions
    use the thresholds set with $set-interrupt-thresholds.  The pin is active
    low unless $active-high is true.  The interrupt stays active until it is
    cleared, which $read-range-mm and $read-measurement do.
  */
  configure-interrupt function/int --active-high/bool=false -> none:
    if function < GPIO-OFF or function > GPIO-NEW-SAMPLE-READY: throw "OUT_OF_RANGE"
    write-u8_ REG-SYSTEM-INTERRUPT-CONFIG-GPIO_ function
    mux := read-u8_ REG-GPIO-HV-MUX-ACTIVE-HIGH_
    mux = active-high ? (mux | 0x10) : (mux & ~0x10)
    write-u8_ REG-GPIO-HV-MUX-ACTIVE-HIGH_ mux
    clear-interrupt

  /**
  Sets the distance thresholds used by the threshold interrupt functions.

  Both are in millimetres.  The sensor stores them with a resolution of 2 mm.
  */
  set-interrupt-thresholds --low-mm/int --high-mm/int -> none:
    if low-mm < 0 or low-mm > 8190: throw "OUT_OF_RANGE"
    if high-mm < 0 or high-mm > 8190: throw "OUT_OF_RANGE"
    write-u16_ REG-SYSTEM-THRESH-LOW_ ((low-mm / 2) & 0x0FFF)
    write-u16_ REG-SYSTEM-THRESH-HIGH_ ((high-mm / 2) & 0x0FFF)

  /** Returns the interrupt thresholds as a list: the low and the high, in mm. */
  get-interrupt-thresholds -> List:
    low := ((read-u16_ REG-SYSTEM-THRESH-LOW_) & 0x0FFF) * 2
    high := ((read-u16_ REG-SYSTEM-THRESH-HIGH_) & 0x0FFF) * 2
    return [low, high]

  // Calibration.

  /**
  Returns the range offset that is added to all measurements, in millimetres.
  The resolution is 0.25 mm.
  */
  get-range-offset-mm -> float:
    raw := (read-u16_ REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_) & 0x0FFF
    if raw > 2047: raw -= 4096
    return raw / 4.0

  /**
  Sets the range offset that is added to all measurements, to $offset-mm.

  The value is stored as a 12-bit number in units of 0.25 mm, so it must be
    between -512 and +511.75.
  */
  set-range-offset-mm offset-mm/num -> none:
    units := (offset-mm * 4.0).round.to-int
    if units < -2048 or units > 2047: throw "OUT_OF_RANGE"
    write-u16_ REG-ALGO-PART-TO-PART-RANGE-OFFSET-MM_ (units & 0x0FFF)

  /**
  Calibrates the range offset using a target at a known distance.

  Place a target (a matt, mid-grey card works) at $target-mm in front of the
    sensor and call this.  It clears the offset, takes $samples measurements,
    and sets the offset to the difference between the target distance and the
    average of the measurements.  Returns the new offset in millimetres.  The
    offset is lost on power loss, so store it and set it again with
    $set-range-offset-mm.

  This is a simple procedure written for this driver.  It is not the
    manufacturer's calibration procedure.
  */
  calibrate-offset --target-mm/int --samples/int=50 -> float:
    if samples < 1: throw "OUT_OF_RANGE"
    set-range-offset-mm 0
    total := 0
    count := 0
    while count < samples:
      total += read-range-mm
      count += 1
    offset := target-mm - (total / samples.to-float)
    set-range-offset-mm offset
    return offset

  /**
  Returns the crosstalk compensation rate, in MCPS.
  A value of 0 means that crosstalk compensation is off.
  */
  get-crosstalk-rate-mcps -> float:
    return (read-u16_ REG-CROSSTALK-COMPENSATION-PEAK-RATE-MCPS_) / 8192.0

  /**
  Sets the crosstalk compensation rate, in MCPS.

  Crosstalk is light that reaches the sensor from a cover glass in front of
    it.  A value of 0 turns the compensation off.  The register has 13
    fractional bits, so the value must be between 0 and 7.99.
  */
  set-crosstalk-rate-mcps rate-mcps/num -> none:
    raw := (rate-mcps * 8192.0).round.to-int
    if raw < 0 or raw > 0xFFFF: throw "OUT_OF_RANGE"
    write-u16_ REG-CROSSTALK-COMPENSATION-PEAK-RATE-MCPS_ raw

  // Timing helpers.

  static decode-vcsel-period_ reg-value/int -> int:
    return (reg-value + 1) << 1

  static encode-vcsel-period_ period-pclks/int -> int:
    return (period-pclks >> 1) - 1

  /** Calculates the macro period in nanoseconds for the given VCSEL period. */
  static calc-macro-period_ vcsel-period-pclks/int -> int:
    return ((2304 * vcsel-period-pclks * 1655) + 500) / 1000

  static decode-timeout_ reg-value/int -> int:
    // The format is "(LSByte * 2^MSByte) + 1".
    return ((((reg-value & 0x00FF) << ((reg-value & 0xFF00) >> 8))) & 0xFFFF) + 1

  static encode-timeout_ timeout-mclks/int -> int:
    // The format is "(LSByte * 2^MSByte) + 1".
    if timeout-mclks <= 0: return 0
    ls-byte := timeout-mclks - 1
    ms-byte := 0
    while (ls-byte & 0xFFFFFF00) > 0:
      ls-byte >>= 1
      ms-byte += 1
    return (ms-byte << 8) | (ls-byte & 0xFF)

  static timeout-mclks-to-us_ timeout-mclks/int vcsel-period-pclks/int -> int:
    macro-period-ns := calc-macro-period_ vcsel-period-pclks
    return ((timeout-mclks * macro-period-ns) + 500) / 1000

  static timeout-us-to-mclks_ timeout-us/int vcsel-period-pclks/int -> int:
    macro-period-ns := calc-macro-period_ vcsel-period-pclks
    return ((timeout-us * 1000) + (macro-period-ns / 2)) / macro-period-ns

  get-step-timeouts_ steps/SequenceSteps_ -> StepTimeouts_:
    timeouts := StepTimeouts_
    timeouts.pre-range-vcsel = get-vcsel-pulse-period VCSEL-PRE-RANGE

    timeouts.msrc-mclks = (read-u8_ REG-MSRC-CONFIG-TIMEOUT-MACROP_) + 1
    timeouts.msrc-us = timeout-mclks-to-us_ timeouts.msrc-mclks timeouts.pre-range-vcsel

    timeouts.pre-range-mclks = decode-timeout_ (read-u16_ REG-PRE-RANGE-CONFIG-TIMEOUT-MACROP-HI_)
    timeouts.pre-range-us = timeout-mclks-to-us_ timeouts.pre-range-mclks timeouts.pre-range-vcsel

    timeouts.final-range-vcsel = get-vcsel-pulse-period VCSEL-FINAL-RANGE

    timeouts.final-range-mclks = decode-timeout_ (read-u16_ REG-FINAL-RANGE-CONFIG-TIMEOUT-MACROP-HI_)
    if steps.pre-range: timeouts.final-range-mclks -= timeouts.pre-range-mclks
    timeouts.final-range-us = timeout-mclks-to-us_ timeouts.final-range-mclks timeouts.final-range-vcsel
    return timeouts

/** Which steps of the measurement sequence are enabled. */
class SequenceSteps_:
  tcc/bool
  dss/bool
  msrc/bool
  pre-range/bool
  final-range/bool

  constructor sequence-config/int:
    tcc = ((sequence-config >> 4) & 1) == 1
    dss = ((sequence-config >> 3) & 1) == 1
    msrc = ((sequence-config >> 2) & 1) == 1
    pre-range = ((sequence-config >> 6) & 1) == 1
    final-range = ((sequence-config >> 7) & 1) == 1

/** The timeouts of the measurement sequence steps. */
class StepTimeouts_:
  pre-range-vcsel/int := 0
  final-range-vcsel/int := 0
  msrc-mclks/int := 0
  pre-range-mclks/int := 0
  final-range-mclks/int := 0
  msrc-us/int := 0
  pre-range-us/int := 0
  final-range-us/int := 0

/**
The result of a measurement of a $Vl53l0x.

The $range-mm is only meaningful if $valid is true.
*/
class Vl53l0xMeasurement:
  /** The measured distance in millimetres. */
  range-mm/int
  /**
  The measurement status: one of $Vl53l0x.STATUS-VALID,
    $Vl53l0x.STATUS-SIGNAL-FAIL, $Vl53l0x.STATUS-MIN-RANGE-FAIL,
    $Vl53l0x.STATUS-PHASE-FAIL, $Vl53l0x.STATUS-HARDWARE-FAIL or
    $Vl53l0x.STATUS-NO-UPDATE.
  */
  status/int
  /** The status code as reported by the sensor, before it was interpreted. */
  raw-status/int
  /** The signal rate of the returned light, in MCPS (million counts per second). */
  signal-rate-mcps/float
  /** The rate of ambient light that reached the sensor, in MCPS. */
  ambient-rate-mcps/float
  /** The effective number of SPADs (light detectors) that received the signal. */
  effective-spads/float

  constructor.from-block_ block/ByteArray:
    raw-status = block[0]
    status = Vl53l0xMeasurement.status-from-raw_ raw-status
    effective-spads = (io.BIG-ENDIAN.uint16 block 2) / 256.0
    signal-rate-mcps = (io.BIG-ENDIAN.uint16 block 6) / 128.0
    ambient-rate-mcps = (io.BIG-ENDIAN.uint16 block 8) / 128.0
    range-mm = io.BIG-ENDIAN.uint16 block 10

  static status-from-raw_ raw/int -> int:
    internal := (raw & 0x78) >> 3
    if internal == 0 or internal == 5 or internal == 7 or internal >= 12:
      return Vl53l0x.STATUS-NO-UPDATE
    if internal == 1 or internal == 2 or internal == 3:
      return Vl53l0x.STATUS-HARDWARE-FAIL
    if internal == 6 or internal == 9:
      return Vl53l0x.STATUS-PHASE-FAIL
    if internal == 8 or internal == 10:
      return Vl53l0x.STATUS-MIN-RANGE-FAIL
    if internal == 4:
      return Vl53l0x.STATUS-SIGNAL-FAIL
    return Vl53l0x.STATUS-VALID

  /** Whether the distance can be trusted. */
  valid -> bool:
    return status == Vl53l0x.STATUS-VALID

  /** A short description of the $status. */
  status-name -> string:
    if status == Vl53l0x.STATUS-VALID: return "valid"
    if status == Vl53l0x.STATUS-SIGMA-FAIL: return "sigma fail"
    if status == Vl53l0x.STATUS-SIGNAL-FAIL: return "signal fail"
    if status == Vl53l0x.STATUS-MIN-RANGE-FAIL: return "min range fail"
    if status == Vl53l0x.STATUS-PHASE-FAIL: return "phase fail"
    if status == Vl53l0x.STATUS-HARDWARE-FAIL: return "hardware fail"
    return "no update"

  stringify -> string:
    return "$range-mm mm ($status-name)"
