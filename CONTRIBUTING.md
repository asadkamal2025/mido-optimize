# 🤝 Contributing to mido-optimize

Thank you for your interest in contributing! This guide will help you get started.

---

## 🎯 How Can I Contribute?

### 🐛 Report Bugs
Found an issue? Help us fix it!

**When reporting:**
```
Title: Brief description of bug
Description:
- Device: Redmi Note 4 (mido)
- Android Version: 11 (LineageOS)
- Magisk Version: v24.0
- Steps to reproduce: 1. ... 2. ...
- Logs: /data/local/tmp/mido_optimize_magisk.log
```

### ✨ Suggest Features
Have a great idea? We'd love to hear it!

### 📝 Improve Documentation
Documentation improvements are always welcome!

### 💻 Submit Code Changes
Performance improvements, bug fixes, and new features welcome!

---

## 🚀 Getting Started

### 1. Fork the Repository
```bash
git clone https://github.com/YOUR_USERNAME/mido-optimize.git
cd mido-optimize
```

### 2. Create a Feature Branch
```bash
git checkout -b feature/your-feature-name
```

### 3. Make Your Changes
- Test thoroughly on device
- Write clear commit messages

### 4. Push to Your Fork
```bash
git push origin feature/your-feature-name
```

### 5. Create a Pull Request
- Go to GitHub
- Click "Compare & pull request"
- Describe your changes
- Submit!

---

## 🎨 Style Guide

### Shell Script Style
```bash
# Good
check_node() {
    if [ -e "$1" ]; then
        return 0
    else
        log "SKIP: $1 not present"
        return 1
    fi
}
```

### Rules
- Use 4 spaces for indentation (not tabs)
- Use lowercase for function names
- Use UPPERCASE for constants
- Add comments for complex logic
- Keep lines under 100 characters

---

## 📞 Community

### Get Help
- Open an issue with detailed info
- Check existing documentation
- Always provide logs

### Stay Updated
- Star the repository
- Watch for releases
- Check CHANGELOG.md

---

**Questions? Open an issue on GitHub!**

Made with ❤️ for the mido community