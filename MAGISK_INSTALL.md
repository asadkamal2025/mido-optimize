# 📦 Magisk Module Installation Guide

## mido-optimize Magisk Module

This directory contains the Magisk module version of mido-optimize, which can be installed directly from Magisk Manager for automatic boot-time optimization.

---

## ✨ Advantages of Magisk Module

✅ **Automatic Installation** - No manual commands needed  
✅ **Boot-Time Execution** - Runs automatically at every boot  
✅ **Persistent Settings** - Changes survive reboots (via system.prop)  
✅ **Easy Uninstall** - Disable module to revert all changes  
✅ **Better Integration** - Works seamlessly with Magisk framework  
✅ **Logging** - Automatic log file generation  

---

## 🔧 Installation Methods

### Method 1: From Magisk Manager (Recommended)
```
1. Open Magisk Manager app
2. Tap "Modules" (bottom navigation)
3. Tap "Install from storage"
4. Select the mido-optimize module ZIP file
5. Restart device
6. Done! ✓
```

### Method 2: Manual Module Installation
```bash
# On your Android device with root:
su
cd /data/adb/modules

# Create module directory
mkdir mido_optimize
cd mido_optimize

# Copy files
cp /path/to/module.prop .
cp /path/to/post-fs-data.sh .
cp /path/to/system.prop .
cp -r /path/to/scripts .

# Fix permissions
chmod 0755 post-fs-data.sh
chmod 0755 scripts/mido_optimize.sh
chmod 0644 scripts/lib/common.sh

# Restart device
reboot
```

---

## 🧩 Shared Helper Library

Both shell scripts source `scripts/lib/common.sh` (logging, sysfs writes,
prop setting, tmpfs handling). Whenever a script is copied somewhere else,
`lib/common.sh` must be copied next to it or it will refuse to start:

```bash
# Example: chrome_colab_guard_v7.sh as a service.d script
su
mkdir -p /data/adb/service.d/lib
cp scripts/chrome_colab_guard_v7.sh /data/adb/service.d/
cp scripts/lib/common.sh /data/adb/service.d/lib/
chmod 0755 /data/adb/service.d/chrome_colab_guard_v7.sh
chmod 0644 /data/adb/service.d/lib/common.sh
```

---

## ✅ Verify Installation

After installing the module:

```bash
# Check if module is active
su
ls -la /data/adb/modules/mido_optimize/

# View optimization log
cat /data/local/tmp/mido_optimize_magisk.log

# Check if properties are applied
getprop ro.lmk.use_psi
getprop ro.lmk.low_ram

# View CPU governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

---

## 🛑 Disable/Uninstall

### Temporarily Disable
```
Magisk Manager → Modules → mido_optimize → Toggle OFF
Restart device
```

### Permanently Uninstall
```
Magisk Manager → Modules → mido_optimize → Delete
Restart device
```

**Result:** All optimizations revert to stock state

---

## 📞 Support

- **Issues:** Open on GitHub
- **Questions:** Check documentation
- **Logs:** Always attach `/data/local/tmp/mido_optimize_magisk.log`

---

**Made with ❤️ for Redmi Note 4 (mido) users**

v1.2 | Magisk Module Ready