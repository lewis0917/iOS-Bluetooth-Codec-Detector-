#pragma once

#import <Foundation/Foundation.h>
#include <notify.h>
#include <stdint.h>

#define kBTCodecNotifName   "com.btcodectweak.codecchanged"

typedef NS_ENUM(uint8_t, BTCodecID) {
    BTCodecID_SBC       = 0x00,
    BTCodecID_MPEG12    = 0x01,
    BTCodecID_AAC       = 0x02,
    BTCodecID_ATRAC     = 0x04,
    BTCodecID_VendorExt = 0xFF,
    BTCodecID_Unknown   = 0xFE,
};

static inline uint64_t BTCodecMakeState(BTCodecID codecID, uint32_t bitrate_kbps) {
    return ((uint64_t)(uint8_t)codecID << 32) | (uint64_t)bitrate_kbps;
}

static inline BTCodecID BTCodecStateGetID(uint64_t state) {
    return (BTCodecID)((state >> 32) & 0xFF);
}

static inline uint32_t BTCodecStateGetBitrate(uint64_t state) {
    return (uint32_t)(state & 0xFFFFFFFFULL);
}
