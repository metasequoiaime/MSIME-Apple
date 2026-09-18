#!/usr/bin/env python3
"""Check desktop key translation against the installed Linux input ABI.

Runs without Tauri/GTK so Linux-only mappings cannot escape host-only tests.
Requires rustc and linux/input-event-codes.h.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'apps/desktop/src-tauri/src/lib.rs').read_text()
header = Path('/usr/include/linux/input-event-codes.h').read_text()
constants = dict(re.findall(r'^#define\s+(KEY_\w+)\s+(\d+)\s*$', header, re.M))


def function(name):
    start = source.index('fn ' + name + '(')
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


keys = [(0x60 + digit, f'KEY_KP{digit}', f'KP_{digit}') for digit in range(10)]
keys += [(0x70 + index, f'KEY_F{index + 1}', f'F{index + 1}') for index in range(12)]
keys += [
    (0x6a, 'KEY_KPASTERISK', 'KP_Multiply'), (0x6b, 'KEY_KPPLUS', 'KP_Add'),
    (0x6c, 'KEY_KPCOMMA', 'KP_Separator'), (0x6d, 'KEY_KPMINUS', 'KP_Subtract'),
    (0x6e, 'KEY_KPDOT', 'KP_Decimal'), (0x6f, 'KEY_KPSLASH', 'KP_Divide'),
    (0x13, 'KEY_PAUSE', 'Pause'), (0x2c, 'KEY_SYSRQ', 'Print'),
    (0x90, 'KEY_NUMLOCK', 'Num_Lock'), (0x91, 'KEY_SCROLLLOCK', 'Scroll_Lock'),
    (0x5b, 'KEY_LEFTMETA', 'Super_L'), (0x5c, 'KEY_RIGHTMETA', 'Super_R'),
    (0x5d, 'KEY_COMPOSE', 'Menu'), (0xa1, 'KEY_RIGHTSHIFT', 'Shift_R'),
    (0xa3, 'KEY_RIGHTCTRL', 'Control_R'), (0xa5, 'KEY_RIGHTALT', 'Alt_R'),
]
checks = []
for vk, kernel, keysym in keys:
    checks.append(f'assert_eq!(ydotool_key_code({vk}), Some({constants[kernel]}), "{kernel}");')
    checks.append(f'assert_eq!(xdotool_key_name({vk}).as_deref(), Some("{keysym}"));')
checks += ['assert_eq!(ydotool_key_code(0), None);', 'assert_eq!(xdotool_key_name(0), None);']
program = function('ydotool_key_code') + '\n' + function('xdotool_key_name')
program += '\nfn main() {\n' + '\n'.join(checks) + '\n}\n'
with tempfile.TemporaryDirectory(prefix='msime-panel-keymap-') as directory:
    path = Path(directory)
    (path / 'main.rs').write_text(program)
    subprocess.run([os.environ.get('RUSTC', 'rustc'), '--edition=2021', '-Dwarnings',
                    str(path / 'main.rs'), '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)
print(f'Linux panel keymap: {len(keys)} keys checked against kernel headers and keysyms')
