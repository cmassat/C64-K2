#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
python3 "$repo_dir/lib/font5x7/generate.py" --check
test_dir=$(mktemp -d /tmp/c64-k2-temperature.XXXXXX)
echo "Temperature regression logs: $test_dir"
cd "$test_dir"
python3 "$repo_dir/K2/test/make_temperature_fixture.py"
cp "$repo_dir/K2/test/xadc_temperature.txt" design.txt
mig_xci=$(sed -n 's|.*<File Path="$PPRDIR/\([^"]*/DDR3_CTRL.xci\)">.*|\1|p' "$repo_dir/K2/build/project/C64-K2-B0C.xpr")
mig_source="$repo_dir/K2/build/project/$(dirname "$mig_xci")/DDR3_CTRL/user_design/rtl/clocking/mig_7series_v4_2_tempmon.v"
if [[ ! -f "$mig_source" ]]; then echo "Generate the K2 MIG project first (expected one tempmon source)"; exit 1; fi
xvhdl --2008 "$repo_dir/M2M/vhdl/cdc_stable.vhd" "$repo_dir/K2/vhdl/k2_temperature_source.vhd"
xvlog "$mig_source"
xvlog "$repo_dir/lib/font5x7/generated/wb_font5x7.v"
xvlog -sv "$repo_dir/K2/rtl/k2_temperature.sv" \
    "$repo_dir/K2/rtl/k2_lcd_temperature.sv" "$repo_dir/K2/rtl/k2_lcd_rle.sv" \
    "$repo_dir/K2/rtl/k2_lcd_splash.sv" "$repo_dir/K2/assets/lcd/c64_logo_rom.sv" \
    "$repo_dir/K2/test/tb_k2_temperature.sv" "$repo_dir/K2/test/tb_k2_lcd_footer.sv" \
    "$repo_dir/K2/test/tb_k2_lcd_snapshot.sv"
xvlog "$XILINX_VIVADO/data/verilog/src/glbl.v"
for bench in tb_k2_temperature tb_k2_xadc tb_k2_lcd_footer tb_k2_lcd_snapshot; do
    xelab "$bench" glbl -L unisims_ver -s "$bench"
    xsim "$bench" -runall | tee "$bench.log"
    rg -q 'PASS:' "$bench.log"
    if rg -q 'FAIL|Fatal:|Error:' "$bench.log"; then exit 1; fi
done
