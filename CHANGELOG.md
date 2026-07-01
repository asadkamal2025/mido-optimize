# Changelog

All notable changes to mido-optimize will be documented in this file.

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
