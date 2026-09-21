/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Matthias Brukner */
#include <assert.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include "wb_font5x7.h"

int main(void) {
    for (unsigned code = 0; code < 256; ++code) {
        uint64_t bits = 0;
        for (unsigned y = 0; y < 7; ++y) {
            uint8_t row = wb_font5x7_row(code, y);
            assert(row <= 31);
            bits = (bits << 5) | row;
            for (unsigned x = 0; x < 5; ++x)
                assert(wb_font5x7_pixel(code, x, y) == ((row >> (4-x)) & 1u));
        }
        assert(wb_font5x7_row(code, 7) == 0);
        assert(wb_font5x7_row(code, UINT_MAX) == 0);
        assert(wb_font5x7_pixel(code, 5, 0) == 0);
        assert(wb_font5x7_pixel(code, 0, 7) == 0);
        assert(wb_font5x7_pixel(code, UINT_MAX, UINT_MAX) == 0);
        printf("%09" PRIx64 "\n", bits);
    }
    assert(wb_font5x7_index(0x100u) == wb_font5x7_index('?'));
    assert(wb_font5x7_index(UINT32_MAX) == wb_font5x7_index('?'));
    return 0;
}
