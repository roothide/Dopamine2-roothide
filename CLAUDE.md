# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is roothide Dopamine 2, an iOS jailbreak application. It's a complex multi-component system consisting of:

- **Application**: iOS app written in Objective-C that provides the user interface and jailbreak functionality
- **BaseBin**: Core jailbreak binaries and daemons written in C/Objective-C
- **Packages**: Debian packages for installation on jailbroken devices

## Build System

### Main Build Commands

```bash
# Build entire project
make

# Build specific components
make -C Application    # Build iOS application
make -C BaseBin        # Build core binaries
make -C Packages       # Build packages

# Clean builds
make clean
make -C Application clean
make -C BaseBin clean
```

### GitHub Actions Build

The project uses GitHub Actions for automated builds. Users can fork the repository and use the workflow at `.github/workflows/roothide.yml` to build their own TIPA files by going to Actions → "build tipa file" → Run Workflow.

### Development Requirements

- **macOS** (required for iOS development)
- **Xcode** with iOS SDK
- **THEOS** jailbreak development framework
- **Procursus** package manager tools (ldid, findutils, sed, coreutils, make)
- **trustcache** tool for iOS code signing

## Architecture

### Application Layer (`Application/`)
- **Dopamine.xcodeproj**: Main iOS application project
- **DOAppDelegate**: Application delegate and lifecycle management
- **Exploits/**: Kernel exploit implementations (badRecovery, dmaFail, kfd)
- **UI/**: User interface components and settings
- Built using Xcode, produces `Dopamine.tipa` file

### Core System (`BaseBin/`)
The BaseBin component builds multiple interdependent system components:

**Core Libraries:**
- `ChOma`: Mach-O manipulation library
- `XPF`: Extended Platform Framework  
- `libjailbreak`: Core jailbreak functionality library

**System Daemons:**
- `jailbreakd`: Main jailbreak daemon
- `bootstrapper`: System bootstrap daemon
- `idownloadd`: Download management daemon

**Hook Libraries:**
- `systemhook`: System call hooks
- `dyldhook`: Dynamic loader hooks
- `launchdhook`: Launch daemon hooks
- `roothidehooks`: roothide-specific hooks
- `watchdoghook`: Watchdog bypass hooks

**Utilities:**
- `jbctl`: Jailbreak control utility
- `boomerang`: Process management
- `forkfix`: Fork system call fixes
- `MachOMerger`: Binary merging utility
- `opainject`: Code injection utility

Build process creates `basebin.tar` containing all compiled components with proper trust cache.

### Package System (`Packages/`)
- `libkrw-provider`: Kernel read/write provider
- `libroot`: Root filesystem access library  
- `basebin-link`: Basebin integration package

## Development Notes

### Build Dependencies
Components have strict build order due to dependencies:
1. ChOma (base library)
2. XPF (depends on ChOma)
3. libjailbreak (depends on ChOma)
4. All other components (depend on libjailbreak)

### Code Signing
- Uses `ldid` for ad-hoc code signing
- Creates trust caches for system binaries
- Application uses custom entitlements in `Dopamine/Dopamine.entitlements`

### Roothide Integration
This is specifically the roothide variant of Dopamine 2, which implements roothide compatibility for rootless jailbreak environments. The build system automatically adds contributor credits to the application.

### Platform Targeting
- **Target**: iOS devices
- **Architecture**: ARM64
- **Minimum iOS**: Determined by exploit compatibility
- **SDK**: iPhone OS SDK (typically latest available)