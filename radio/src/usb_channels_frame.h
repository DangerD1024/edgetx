/*
 * Copyright (C) EdgeTX
 *
 * License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

// USB RC Channels streaming protocol
//
// Wire format (little-endian, 1 frame per mixer cycle):
//
//   +------+------+------+------------------------------+------+
//   | SYNC | TYPE | SEQ  |   payload (CH_COUNT*2 bytes) | CRC  |
//   +------+------+------+------------------------------+------+
//      1B    1B     1B               64B                   1B    = 68B total
//
// SYNC    = 0xFE
// TYPE    = 0x10  (channel data, 32 x uint16, little-endian)
// SEQ     = monotonically incrementing wrap-at-255 sequence number
// payload = CH_COUNT little-endian uint16; value = clamp(channelOutputs[i] + 1024, 0, 2047)
//           (same encoding as the existing HID classic axis values, see
//            radio/src/usb_joystick.cpp:578)
// CRC     = CRC-8/DVB-S2, polynomial 0xD5, init 0x00, computed over TYPE..payload
//
// The host bridge identifies the device by USB descriptor:
//   VID = 0x1209  (pid.codes)
//   PID = 0x4F55
//   Product string contains "RC Channels"

#pragma once

#include <stdint.h>

#define USB_CHANNELS_FRAME_SYNC      0xFE
#define USB_CHANNELS_FRAME_TYPE_DATA 0x10
#define USB_CHANNELS_FRAME_CH_COUNT  32
#define USB_CHANNELS_FRAME_SIZE      (1 + 1 + 1 + USB_CHANNELS_FRAME_CH_COUNT * 2 + 1)

#ifdef __cplusplus
extern "C" {
#endif

static inline uint8_t usbChannelsCrc8(const uint8_t* data, uint32_t len)
{
  uint8_t crc = 0;
  for (uint32_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (uint8_t b = 0; b < 8; b++) {
      crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0xD5) : (uint8_t)(crc << 1);
    }
  }
  return crc;
}

#ifdef __cplusplus
}
#endif
