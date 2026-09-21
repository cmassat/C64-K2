#!/usr/bin/env bash
# Source Vivado settings64.sh first.  The C64 logo generator is self-contained,
# so unlike AExp-K2's this suite needs no Pillow or rsvg-convert.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
python3 "$repo_dir/lib/font5x7/generate.py" --check
test_dir=$(mktemp -d /tmp/c64-k2-lcd.XXXXXX)
echo "LCD regression logs: $test_dir"
python3 "$repo_dir/K2/scripts/generate_c64_logo.py" --output-dir "$test_dir" --test-vectors
cmp "$repo_dir/K2/assets/lcd/c64_logo_rom.sv" "$test_dir/c64_logo_rom.sv"
cd "$test_dir"
xvlog "$repo_dir/lib/font5x7/generated/wb_font5x7.v"
xvlog -sv "$repo_dir/K2/rtl/k2_lcd_rle.sv" \
    "$repo_dir/K2/rtl/k2_lcd_splash.sv" \
    "$repo_dir/K2/rtl/k2_temperature.sv" \
    "$repo_dir/K2/rtl/k2_lcd_temperature.sv" \
    "$repo_dir/K2/assets/lcd/c64_logo_rom.sv" \
    "$repo_dir/K2/test/tb_k2_lcd_splash.sv"
for variant in small long logo; do
    generic=()
    if [[ $variant == long ]]; then generic=(-generic_top LONG_RUNS=1); fi
    if [[ $variant == logo ]]; then generic=(-generic_top REAL_LOGO=1); fi
    xelab tb_k2_lcd_splash "${generic[@]}" -s "lcd_$variant"
    xsim "lcd_$variant" -runall | tee "$variant.log"
    rg -q 'PASS:' "$variant.log"
    if rg -q 'FAIL|Fatal:|Error:' "$variant.log"; then exit 1; fi
done
