#!/usr/bin/env bash
# Source Vivado settings64.sh first. Keep logs, including the expected failure.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/c64-k2-memory-order.XXXXXX)
echo "Memory ordering regression logs: $test_dir"
cd "$test_dir"
xvhdl --2008 "$repo_dir/M2M/vhdl/memory/avm_arbit.vhd" \
  "$repo_dir/K2/vhdl/k2_avm_read_guard.vhd" \
  "$repo_dir/K2/test/tb_k2_avm_read_order.vhd" \
  "$repo_dir/K2/test/tb_k2_avm_read_guard.vhd"
xelab tb_k2_avm_read_order -generic_top G_SERIALIZE=false -s unguarded_sim
xsim unguarded_sim -runall | tee unguarded.log
rg -q 'Failure: Read response ownership corrupted' unguarded.log
rg -q 'owner=3, incorrectly to competitor=1' unguarded.log
xelab tb_k2_avm_read_order -generic_top G_SERIALIZE=true -s guarded_sim
xsim guarded_sim -runall | tee guarded.log
rg -q 'PASS:' guarded.log
if rg -q 'Failure:|Fatal:|Error:' guarded.log; then exit 1; fi
xelab tb_k2_avm_read_guard -s guard_unit_sim
xsim guard_unit_sim -runall | tee guard_unit.log
rg -q 'PASS:' guard_unit.log
if rg -q 'Failure:|Fatal:|Error:' guard_unit.log; then exit 1; fi
echo 'PASS: memory ordering regression (unguarded failure reproduced, guarded tests pass)'
