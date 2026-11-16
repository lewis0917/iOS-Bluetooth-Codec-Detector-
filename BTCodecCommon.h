// BTCodecCommon.h
// Shared constants, types, and inline helpers consumed by both compilation
// units. Include-guarded; both targets add the project root to their -I path.

#pragma once

#import  <Foundation/Foundation.h>
#include <notify.h>
#include <stdint.h>

// ── Darwin notification names ──────────────────────────────────────────────────
#define kBTCodecNotifName       "com.btcodectweak.codecchanged"
#define kBTCodecPrefsChanged    "com.btcodectweak.prefschanged"

// ── A2DP AVDTP payload-type codec IDs (A2DP spec §4.3) ───────────────────────
typedef NS_ENUM(uint8_t, BTCodecID) {
    BTCodecID_SBC       = 0x00,
    BTCodecID_MPEG12    = 0x01,
    BTCodecID_AAC       = 0x02,
    BTCodecID_ATRAC     = 0x04,
    BTCodecID_VendorExt = 0xFF,
    BTCodecID_Unknown   = 0xFE,
};

// ── notify_set_state payload encoding ─────────────────────────────────────────
// Bit 63 — validity flag. Always set on real daemon posts.
//           An uninitialised notify state reads as 0, which previously
//           decoded as BTCodecID_SBC (0x00) — a silent false positive.
//           Any state without bit 63 set is ignored by the UI layer.
// Bits 32–39 — codec ID byte.
// Bits  0–31 — estimated bitrate in kbps (0 = not determined).

static inline uint64_t BTCodecMakeState(BTCodecID codecID, uint32_t bitrate_kbps) {
    return ((uint64_t)1          << 63)   // validity flag
         | ((uint64_t)(uint8_t)codecID << 32)
         | (uint64_t)bitrate_kbps;
}

static inline BOOL BTCodecStateIsValid(uint64_t state) {
    return (BOOL)((state >> 63) & 1);
}

static inline BTCodecID BTCodecStateGetID(uint64_t state) {
    return (BTCodecID)((state >> 32) & 0xFF);
}

static inline uint32_t BTCodecStateGetBitrate(uint64_t state) {
    return (uint32_t)(state & 0xFFFFFFFFULL);
}
