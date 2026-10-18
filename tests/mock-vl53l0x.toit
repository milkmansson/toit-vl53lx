// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import serial

/**
A very small simulation of a VL53L0X register file.

It is deliberately simple.  It exists to check the order and the content of the
  register accesses of the driver, not to simulate the optics.  The same model
  is implemented in tests/trace-harness/Wire.h, so that traces recorded with
  other libraries can be compared with traces recorded with this one.

Behaviour:
- Writes are stored and reads return the stored value, except for the
  registers listed in $model_.
- The preloaded result block describes a valid measurement of 300 mm.
- Every access is recorded in $trace, one line per access: "R reg count" for
  reads and "W reg byte byte ..." for writes.
*/
class MockVl53l0xRegisters extends serial.Registers:
  regs_/ByteArray := ByteArray 256
  /** The recorded register accesses and the markers added with $mark. */
  trace/List := []
  /** The value of the model ID register. */
  model-id/int := 0xEE

  constructor:
    // Preloaded result block: status valid (11 << 3), 10 effective SPADs
    // (8.8), signal 2 MCPS (9.7), ambient 0.5 MCPS (9.7), range 300 mm.
    regs_[0x14] = 0x58
    regs_[0x16] = 0x0A
    regs_[0x17] = 0x00
    regs_[0x1A] = 0x01
    regs_[0x1B] = 0x00
    regs_[0x1C] = 0x00
    regs_[0x1D] = 0x40
    regs_[0x1E] = 0x01
    regs_[0x1F] = 0x2C
    // Oscillator calibration value.
    regs_[0xF8] = 0x0C
    regs_[0xF9] = 0x80
    // Reference SPAD map.
    6.repeat: regs_[0xB0 + it] = 0xFF

  /** Adds a marker line to the $trace. */
  mark text/string -> none:
    trace.add "# $text"

  /** Sets the preloaded range result, in millimetres. */
  set-range mm/int -> none:
    regs_[0x1E] = mm >> 8
    regs_[0x1F] = mm & 0xFF

  /** Sets the raw status byte in the preloaded result block. */
  set-raw-status value/int -> none:
    regs_[0x14] = value

  model_ register/int -> int:
    if register == 0xC0: return model-id
    if register == 0xC1: return 0xAA
    if register == 0xC2: return 0x10
    if register == 0x83: return 0x01  // SPAD info strobe is always done.
    if register == 0x92: return 0x8C  // Aperture SPADs, count 12.
    if register == 0x13: return 0x07  // Interrupt status: always ready.
    if register == 0x91: return 0x3C  // Stop variable.
    if register == 0x00: return 0x00  // Start bit is always clear.
    return regs_[register]

  read-bytes register/int count/int -> ByteArray:
    trace.add "R $(%02X register) $count"
    return ByteArray count: model_ ((register + it) & 0xFF)

  write-bytes register/int data/ByteArray -> none:
    line := "W $(%02X register)"
    data.size.repeat:
      line += " $(%02X data[it])"
      regs_[(register + it) & 0xFF] = data[it]
    trace.add line

/** A device that exposes the simulated registers. */
class MockVl53l0xDevice implements serial.Device:
  registers_/MockVl53l0xRegisters
  pointer_/int := 0

  constructor .registers_:

  registers -> serial.Registers:
    return registers_

  /** Raw read from the register selected by the last raw write. */
  read amount/int -> ByteArray:
    return registers_.read-bytes pointer_ amount

  /** Raw write: one byte selects the register, more bytes are written there. */
  write bytes/ByteArray -> none:
    if bytes.size == 0: throw "short write"
    pointer_ = bytes[0]
    if bytes.size > 1: registers_.write-bytes bytes[0] bytes[1..]
