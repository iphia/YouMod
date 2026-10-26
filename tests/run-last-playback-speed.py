#!/usr/bin/env python3
"""Run macOS Foundation regression tests against the real playback hook bodies."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
player = (root / 'Files/Player.x').read_text()

def method(signature):
    start = player.index(signature, player.index('%hook YTPlayerViewController'))
    end = player.index('\n}', start) + 2
    return player[start:end].replace('%orig;', 'self.rate = rate;')

source = (root / 'tests/last-playback-speed.m').read_text().replace(
    '// PLAYER_METHODS', method('- (void)setPlaybackRate:(float)rate {') + '\n' +
    method('- (void)YouModSetAutoSpeed {'))
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp)
    (path / 'test.m').write_text(source)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                    '-framework', 'Foundation', '-I', str(root / 'Files'),
                    str(path / 'test.m'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)
