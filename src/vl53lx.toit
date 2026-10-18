// Copyright (C) 2026 Toit Contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import io
import log
import serial

import .vl53l0x
import .vl53l1x

export *

/**
Identification of ST time-of-flight sensors and automatic selection of the driver.

Breakout boards for the VL53L0X and VL53L1X look alike, and the silkscreen is
  not always readable.  Use $identify to find out which chip is on the board,
  or $open to get the matching driver directly.

The two families are told apart by their ID registers:
- The VL53L0X has 8-bit register indexes and reports 0xEE in register 0xC0.
- The VL53L1X (and the related VL53L4CD) have 16-bit register indexes and
  report a 16-bit model ID in register 0x010F: 0xEACC for the VL53L1X, 0xEBAA
  for the VL53L4CD.

The probing order matters.  The VL53L0X is probed first, with a one-byte
  register index.  Only if that fails is the 16-bit probe used: a two-byte
  index written to a VL53L0X would be taken as "write the second byte to
  register 0x01", which is its sequence-config register.  A one-byte write to a
  VL53L1X only sets half of an index and is believed to be harmless (not
  verified on hardware).

# Examples
```
import i2c
import vl53lx show *

main:
  bus := i2c.Bus --sda=21 --scl=20
  device := bus.device 0x29
  print (identify device)
  sensor := open device
  print sensor.read-range-mm
```
*/

/** Kind of sensor found by $identify: a VL53L0X. */
KIND-VL53L0X ::= "VL53L0X"
/** Kind of sensor found by $identify: a VL53L1X. */
KIND-VL53L1X ::= "VL53L1X"
/** Kind of sensor found by $identify: a VL53L4CD (identified only; no driver in this package). */
KIND-VL53L4CD ::= "VL53L4CD"
/** Kind of sensor found by $identify: nothing known answered. */
KIND-UNKNOWN ::= "unknown"

/** The result of $identify. */
class Identification:
  /** The kind of sensor: one of $KIND-VL53L0X, $KIND-VL53L1X, $KIND-VL53L4CD, $KIND-UNKNOWN. */
  kind/string
  /** The bytes read from 0xC0, 0xC1 and 0xC2 (8-bit index probe), or null if the read failed. */
  raw-8bit/ByteArray?
  /** The bytes read from 0x010F, 0x0110 and 0x0111 (16-bit index probe), or null if it wasn't done or failed. */
  raw-16bit/ByteArray?

  constructor.private_ .kind .raw-8bit .raw-16bit:

  /** Whether the sensor can be used with $Vl53l0x. */
  is-vl53l0x -> bool:
    return kind == KIND-VL53L0X

  /** Whether the sensor can be used with $Vl53l1x. */
  is-vl53l1x -> bool:
    return kind == KIND-VL53L1X

  stringify -> string:
    parts := ["$kind"]
    if raw-8bit != null: parts.add "0xC0..C2 = $(hex_ raw-8bit)"
    if raw-16bit != null: parts.add "0x010F..0111 = $(hex_ raw-16bit)"
    return parts.join "; "

  static hex_ bytes/ByteArray -> string:
    parts := []
    bytes.do: parts.add "$(%02X it)"
    return parts.join " "

/**
Identifies the sensor behind the $device.

Never throws for a missing or unknown chip; check the $Identification.kind.
  The raw bytes are included so that an unknown chip can still be investigated.
*/
identify device/serial.Device -> Identification:
  raw-8bit/ByteArray? := null
  raw-16bit/ByteArray? := null
  catch:
    device.write #[0xC0]
    raw-8bit = device.read 3
  if raw-8bit != null and raw-8bit[0] == Vl53l0x.MODEL-ID:
    return Identification.private_ KIND-VL53L0X raw-8bit null
  catch:
    device.write #[0x01, 0x0F]
    raw-16bit = device.read 3
  if raw-16bit != null:
    id := io.BIG-ENDIAN.uint16 raw-16bit 0
    if id == Vl53l1x.MODEL-ID: return Identification.private_ KIND-VL53L1X raw-8bit raw-16bit
    if id == 0xEBAA: return Identification.private_ KIND-VL53L4CD raw-8bit raw-16bit
  return Identification.private_ KIND-UNKNOWN raw-8bit raw-16bit

/**
Identifies the sensor behind the $device and returns the matching driver,
  a $Vl53l0x or a $Vl53l1x, constructed with its defaults.

Throws if the sensor is not a VL53L0X or VL53L1X.  Use the driver
  constructors directly to pass options.
*/
open device/serial.Device --logger/log.Logger=log.default:
  identification := identify device
  if identification.is-vl53l0x: return Vl53l0x device --logger=logger
  if identification.is-vl53l1x: return Vl53l1x device --logger=logger
  throw "Unsupported or missing sensor: $identification"
