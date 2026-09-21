#!/usr/bin/env bash
# Source Vivado settings64.sh first.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/c64-k2-leds.XXXXXX)
echo "LED regression logs: $test_dir"
cd "$test_dir"
xvhdl --2008 "$repo_dir/K2/vhdl/k2_status_leds.vhd" "$repo_dir/K2/test/tb_k2_status_leds.vhd"
xelab tb_k2_status_leds -s leds_sim
xsim leds_sim -runall | tee result.log
rg -q 'PASS:' result.log
if rg -q 'Failure:|Fatal:|Error:' result.log; then exit 1; fi
