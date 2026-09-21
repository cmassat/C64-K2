#!/usr/bin/env bash
# Source Vivado settings64.sh first.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/c64-k2-rtc-test.XXXXXX)
echo "RTC regression logs: $test_dir"
cd "$test_dir"
xvhdl --2008 "$repo_dir/M2M/vhdl/cdc_stable.vhd" \
    "$repo_dir/K2/vhdl/k2_rtc.vhd" "$repo_dir/K2/test/tb_k2_rtc.vhd"
xelab tb_k2_rtc -s rtc_sim
xsim rtc_sim -runall | tee result.log
rg -q 'PASS:' result.log
if rg -q 'Failure:|Fatal:|Error:' result.log; then exit 1; fi
# AExp-K2 followed this with a decoder regression extracted from Minimig's
# private RTC block (make_rtc_decode_fixture.py + tb_rtc_decode.sv).  That is
# Amiga-specific; the C64 equivalent would target M2M's rtc_controller.vhd.
# See K2/README.md, milestone M5.
