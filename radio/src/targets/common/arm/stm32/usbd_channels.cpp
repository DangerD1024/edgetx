/*
 * Copyright (C) EdgeTX
 *
 * License GPLv2: http://www.gnu.org/licenses/gpl-2.0.html
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

// USB CDC-class endpoint that streams all radio channel outputs to the host
// at the mixer rate. The wire format is documented in usb_channels_frame.h
// and the device is identified to the host by a distinct VID/PID and product
// string (see usbd_desc.c).

#include "hal/usb_driver.h"

#if defined(USB_CHANNELS)

#include "usb_channels_frame.h"
#include "edgetx_helpers.h"  // limit<>
#include "globals.h"         // channelOutputs[]
#include "dataconstants.h"   // MAX_OUTPUT_CHANNELS

extern "C" {
#include "usb_conf.h"
#include "usbd_cdc.h"
}

extern USBD_HandleTypeDef hUsbDevice;

static_assert(USB_CHANNELS_FRAME_CH_COUNT <= MAX_OUTPUT_CHANNELS,
              "Frame channel count exceeds available outputs");

static uint8_t _channelsRxBuffer[CDC_DATA_FS_OUT_PACKET_SIZE];
static uint8_t _channelsTxBuffer[USB_CHANNELS_FRAME_SIZE];
static uint8_t _channelsSeq = 0;

extern "C" {

static int8_t Channels_Init_FS(void)
{
  USBD_CDC_SetTxBuffer(&hUsbDevice, _channelsTxBuffer, 0);
  USBD_CDC_SetRxBuffer(&hUsbDevice, _channelsRxBuffer);
  return USBD_OK;
}

static int8_t Channels_DeInit_FS(void)
{
  return USBD_OK;
}

static int8_t Channels_Control_FS(uint8_t cmd, uint8_t* /*pbuf*/, uint16_t /*length*/)
{
  // CDC line-coding requests are accepted but ignored — the device is not
  // a real serial port and has no baud rate to honour.
  (void)cmd;
  return USBD_OK;
}

static int8_t Channels_Receive_FS(uint8_t* Buf, uint32_t* /*Len*/)
{
  // Host-to-radio data is unused for now; just re-arm OUT endpoint.
  USBD_CDC_SetRxBuffer(&hUsbDevice, Buf);
  USBD_CDC_ReceivePacket(&hUsbDevice);
  return USBD_OK;
}

static int8_t Channels_TransmitCplt_FS(uint8_t* /*Buf*/, uint32_t* /*Len*/, uint8_t /*epnum*/)
{
  return USBD_OK;
}

static int8_t Channels_StartOfFrame_FS(void)
{
  // We push frames from the mixer task (usbChannelsUpdate). SOF is unused.
  return USBD_OK;
}

USBD_CDC_ItfTypeDef USBD_Channels_Interface_fops = {
  Channels_Init_FS,
  Channels_DeInit_FS,
  Channels_Control_FS,
  Channels_Receive_FS,
  Channels_TransmitCplt_FS,
  Channels_StartOfFrame_FS,
};

}  // extern "C"

static void buildChannelFrame(uint8_t* out, uint8_t seq)
{
  out[0] = USB_CHANNELS_FRAME_SYNC;
  out[1] = USB_CHANNELS_FRAME_TYPE_DATA;
  out[2] = seq;

  uint8_t* payload = out + 3;
  for (uint8_t i = 0; i < USB_CHANNELS_FRAME_CH_COUNT; i++) {
    int16_t v = limit<int16_t>(0, channelOutputs[i] + 1024, 2047);
    payload[i * 2]     = (uint8_t)(v & 0xFF);
    payload[i * 2 + 1] = (uint8_t)((v >> 8) & 0xFF);
  }

  // CRC over TYPE..payload (everything between SYNC and CRC)
  out[USB_CHANNELS_FRAME_SIZE - 1] =
      usbChannelsCrc8(out + 1, USB_CHANNELS_FRAME_SIZE - 2);
}

void usbChannelsInit()
{
  _channelsSeq = 0;
}

void usbChannelsUpdate()
{
  USBD_CDC_HandleTypeDef* hcdc =
      (USBD_CDC_HandleTypeDef*)hUsbDevice.pClassData;
  if (hcdc == nullptr) return;

  // Drop the frame if the previous one is still in flight — newer is better
  // than queued-and-stale for control data.
  if (hcdc->TxState != 0) return;

  buildChannelFrame(_channelsTxBuffer, _channelsSeq++);
  USBD_CDC_SetTxBuffer(&hUsbDevice, _channelsTxBuffer, USB_CHANNELS_FRAME_SIZE);
  USBD_CDC_TransmitPacket(&hUsbDevice);
}

#endif  // USB_CHANNELS
