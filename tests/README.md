Run `python3 tests/run-last-playback-speed.py` on macOS with Xcode command-line tools.
The test compiles the shared helpers and actual Player.x hook bodies against Foundation,
with a mock player and isolated preferences. It does not emulate YouTube or Logos hook chaining.

Device checks before release:
- Select Player > Default playback speed > Last playback speed. With no saved rate, playback starts at 1x.
- Set a normal video's speed to 1.75x, open another video, and relaunch the app: 1.75x should be restored.
- Change back to 1x and verify that it is remembered too.
- Select 2.5x in the Shorts speed menu and page to another Short; verify 2.5x remains active.
- Verify ads and temporary hold-to-speed boosts/locks do not replace the saved normal speed.
- Select a fixed default or Disabled and verify the existing behavior.
