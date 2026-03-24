# GodotSteam GDExtension Setup

This folder needs the GodotSteam GDExtension binaries to enable Steam multiplayer.

## Download

1. Go to **https://codeberg.org/godotsteam/godotsteam/releases**
2. Download **v4.17.1-gde** (or latest GDExtension release compatible with Godot 4.4+)
3. Extract the archive

## Install

Copy the following into this folder (`addons/godotsteam/`):

- `godotsteam.gdextension` (from archive root)
- `win64/` folder (Windows: `.dll` files + `steam_api64.dll`)
- `osx/` folder (macOS: `.dylib` files + `libsteam_api.dylib`)
- `linux64/` folder (Linux: `.so` files + `libsteam_api.so`)

### Expected structure

```
addons/godotsteam/
├── godotsteam.gdextension
├── win64/
│   ├── libgodotsteam.windows.template_debug.x86_64.dll
│   ├── libgodotsteam.windows.template_release.x86_64.dll
│   └── steam_api64.dll
├── osx/
│   ├── libgodotsteam.macos.template_debug.universal.dylib
│   ├── libgodotsteam.macos.template_release.universal.dylib
│   └── libsteam_api.dylib
└── linux64/
    ├── libgodotsteam.linuxbsd.template_debug.x86_64.so
    ├── libgodotsteam.linuxbsd.template_release.x86_64.so
    └── libsteam_api.so
```

## Development Testing

- `steam_appid.txt` in the project root is set to `480` (Valve's SpaceWar test app)
- Steam must be running on your machine for the game to initialize
- Replace `480` with your real Steam App ID before release
- Both host and joining player need Steam running
- Friends join via Steam friend list: right-click -> "Join Game"
