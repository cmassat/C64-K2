#!/usr/bin/env bash
# Source Vivado settings64.sh first. All simulator products stay in /tmp.
set -euo pipefail
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d /tmp/c64-k2-keyboard.XXXXXX)
echo "Keyboard regression logs: $test_dir"
cd "$repo_dir"
tclsh <<'TCL'
source K2/scripts/config_variant.tcl
puts [k2_config_variant [pwd]]
TCL

run_test() {
    local name=$1
    shift
    mkdir "$test_dir/$name"
    cd "$test_dir/$name"
    xvhdl --2008 "$@" "$repo_dir/K2/test/$name.vhd"
    xelab "$name" -s test_sim
    xsim test_sim -runall | tee result.log
    rg -q 'PASS:' result.log
    if rg -q 'Failure:|Fatal:|Error:' result.log; then return 1; fi
}
run_test tb_k2_optical "$repo_dir/K2/vhdl/k2_keyboard_matrix.vhd" \
    "$repo_dir/K2/vhdl/k2_m2m_keyb.vhd"
run_test tb_k2_restore "$repo_dir/K2/vhdl/k2_keyboard_matrix.vhd" \
    "$repo_dir/K2/vhdl/k2_m2m_keyb.vhd"
run_test tb_k2_menu "$repo_dir/K2/build/generated/config.vhd"
# AExp-K2 ran tb_k2_keymap here, asserting raw Amiga scancodes out of
# CORE/vhdl/keyboard.vhd.  C64MEGA65's keyboard.vhd drives the CIA-1 matrix
# instead, and the K2 optical matrix already uses C64 cell numbering, so that
# testbench needs rewriting rather than porting.  See K2/README.md, M2.
