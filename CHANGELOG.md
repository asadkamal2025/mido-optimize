# Changelog

All notable changes to mido-optimize will be documented in this file.

## [scripts/chrome_colab_guard_v7.sh] - 2026-07-07

### Added
- `chrome_colab_guard_v7.sh`: Magisk `service.d` guard script that protects
  Chrome (and long-running Colab tab sessions) from aggressive LMKD kills
  on mido (4GB RAM, SD625) without starving the rest of a GApps-heavy setup.

### Fixed (vs internal v6 draft, verified in a sandboxed shell before shipping)
- **Timestamp forking**: `log()` forked `date` on every single line (O(N)
  forks per tick for N chrome PIDs). Now caches one timestamp per loop tick.
- **PID enumeration forking**: scanning `/proc/*/cmdline` forked `tr` per
  candidate PID every 8-20s. Now a single `grep -laF` prefilter + shell
  `case` classification (zero extra forks), which also fixed a **false
  match bug**: naive anchored regexes (`^pkg$`) never match because
  `/proc/pid/cmdline` is NUL-*terminated*, not newline-terminated, and
  embedding a literal NUL into a shell-quoted regex is not portable
  (confirmed broken in testing).
- **`/proc/pid/stat` nice parsing bug**: the naive `awk '{print $19}'`
  approach (and an earlier bugfix attempt using bare `$17`, which shells
  parse as `$1` followed by literal `7`, not positional parameter 17) both
  silently misread the nice value whenever a thread name (`comm`) contained
  a space, e.g. `(GLThread 61)`. Fixed by splitting on the last `") "` per
  proc(5) and using `${17}`. Verified against synthetic `/proc` fixtures.
- **Blanket process protection**: v6 shielded every chrome-tagged PID
  (main process, GPU process, every renderer) equally with
  `oom_score_adj=-300`. This fights Android's own background-tab reclaim
  and just shifts LMKD's kill pressure onto unrelated apps. v7 gives strong
  protection only to the exact main process and a much milder, capped
  adjustment to child/renderer/GPU processes.
- **One-shot tmpfs safety check**: `/data/local/tmp` tmpfs mount safety was
  only checked once at boot. v7 periodically re-checks `MemAvailable` and
  auto-unmounts if memory becomes critically low, so tmpfs can't become a
  self-inflicted OOM contributor during a heavy Colab session.

## [1.2] - 2026-06-20

### Added
- Comprehensive error handling and validation
- Root user check at startup (exits cleanly if not root)
- Better logging with timestamps and ✓ success indicators
- Detailed comments for each optimization section
- `update.json` for Magisk auto-update support
- Explicit variable expansion instead of `$_` for shell portability

### Improved
- Script structure and readability across both `mido_optimize.sh` and `scripts/mido_optimize.sh`
- Error messages and debugging info
- Log formatting and clarity
- `module.prop` now includes `updateJson` field
- Overall code quality

### Fixed
- `scripts/mido_optimize.sh` was empty — now contains full script
- Replaced `$_` shorthand with explicit paths for POSIX sh compatibility

## [1.1] - 2026-06-06

### Initial Release
- DeGoogle functionality (disable Google services)
- Memory optimization (LMKD + VM tuning)
- CPU interactive governor tuning
- GPU optimization (Adreno 506)
- Logging reduction
- Production-safe design with node checking

---

## [Planned]

### v1.3
- [ ] Android 12+ support testing
- [ ] Additional ROM compatibility (HavocOS, AOSP variants)
- [ ] User configuration file (.config)
- [ ] System restore point before optimization

### v2.0
- [ ] GUI app for easier installation
- [ ] Real-time performance monitoring
- [ ] Before/after benchmarking
- [ ] Custom profile selection

## v3.0 - GApps Performance Build
- Removed DeGoogle package disables (GMS/GSF/Play Store no longer touched)
- Added targeted disable for only non-essential background components (Play Games, Wellbeing, Feedback, Print recommendation)
- Added GMS doze-whitelist enforcement so push notifications survive
- PSI-based LMKd tuning biased to protect GMS from repeated restart-kills (kill_timeout raised to 2500ms)
- Relaxed periodic sync interval to 30min (push via FCM unaffected)
- Retained CPU interactive governor tuning, Adreno 506 GPU tuning
- Retained tmpfs /cache mount for fast GApps DB writes (648 MB/s verified)
