# Rebuild the C64MEGA65 QNICE firmware before K2 synthesis, as the MEGA65 projects
# do.  A fresh Linux checkout may not yet contain QNICE's generated native
# assembler or dist_kit files, so create only the missing build products.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ../..]]
source [file join $script_dir config_variant.tcl]
k2_config_variant $repo_dir
set qnice_dir  [file join $repo_dir M2M QNICE]
set qasm       [file join $qnice_dir assembler qasm]
set qasm2rom   [file join $qnice_dir assembler qasm2rom]

if {![file executable $qasm]} {
   exec cc -O2 -o $qasm [file join $qnice_dir assembler qasm.c]
}
if {![file executable $qasm2rom]} {
   exec cc -O2 -std=c99 -o $qasm2rom \
      [file join $qnice_dir assembler qasm2rom.c]
}

if {![file exists [file join $qnice_dir dist_kit sysdef.asm]]} {
   set saved_dir [pwd]
   cd [file join $qnice_dir monitor]
   exec ./compile_and_distribute.sh <@stdin >@stdout 2>@stderr
   cd $saved_dir
}

set saved_dir [pwd]
cd [file join $repo_dir CORE m2m-rom]
exec ./make_rom.sh <@stdin >@stdout 2>@stderr
cd $saved_dir

set firmware [file join $repo_dir CORE m2m-rom m2m-rom.rom]
if {![file exists $firmware] || [file size $firmware] == 0} {
   error "QNICE firmware generation did not produce $firmware"
}
