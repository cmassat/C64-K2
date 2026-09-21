#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Matthias Brukner
"""Check generated files and C/C++ exports; optionally simulate Verilog."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from generate import ROOT, CODES, load_font, outputs


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hdl', choices=('vivado', 'iverilog'), help='Also test Verilog-2001 with this simulator')
    args = parser.parse_args()
    data = load_font()
    for name, content in outputs(data).items():
        assert (ROOT / 'generated' / name).read_text(encoding='utf-8') == content, name
    patterns = data['glyphs']
    assert patterns[' '] == '/'.join(['00000']*7)
    assert all('1' in patterns[chr(code)] for code in CODES if code != 0x20)
    assert patterns['0'] != patterns['O']
    assert len({patterns[c] for c in '1Il'}) == 3
    expected = [int(patterns.get(chr(code), patterns['?']).replace('/', ''), 2) for code in range(256)]
    scratch = Path(tempfile.mkdtemp(prefix='wb-font5x7-'))
    print(f'Font regression logs/artifacts: {scratch}', flush=True)
    for compiler, standard in [('cc', 'c99'), ('c++', 'c++11')]:
        executable = scratch / compiler.replace('+', 'x')
        command = [compiler, f'-std={standard}', '-Wall', '-Wextra', '-Werror', '-pedantic',
                   '-I', str(ROOT / 'generated'), '-o', str(executable)]
        if compiler == 'c++':
            command += ['-x', 'c++']
        command += [str(ROOT / 'tests' / 'test_font.c')]
        run(command, scratch)
        actual = [int(line, 16) for line in run([str(executable)], scratch).splitlines()]
        assert actual == expected, compiler
    print('PASS: source geometry, all 256 codes in C99/C++11, pixel orientation, bounds and fallback')
    if args.hdl:
        (scratch / 'font.mem').write_text(''.join(f'{bits:09x}\n' for bits in expected))
        sources = [str(ROOT / 'generated' / 'wb_font5x7.v'), str(ROOT / 'tests' / 'tb_font.v')]
        if args.hdl == 'vivado':
            run(['xvlog'] + sources, scratch)
            run(['xelab', 'tb_font', '-s', 'font_sim'], scratch)
            log = run(['xsim', 'font_sim', '-runall'], scratch)
        else:
            run(['iverilog', '-g2001', '-s', 'tb_font', '-o', 'font_sim'] + sources, scratch)
            log = run(['vvp', 'font_sim'], scratch)
        (scratch / 'simulation.log').write_text(log)
        assert 'PASS:' in log and 'FAIL:' not in log and 'Fatal:' not in log, log
        print('PASS: Verilog-2001 lookup matches all 256 canonical codepoints')


if __name__ == '__main__':
    main()
