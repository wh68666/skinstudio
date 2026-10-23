# References and attribution

SkinStudio combines the local ZCode Skin implementation with the architecture of
[MonkeyCode Skin](https://github.com/wh68666/monkeyscode-skin), both maintained by
the same repository owner. It retains their PowerShell/WPF interface, ZIP importer,
gallery integration and CDP client, with separate application adapters.

[Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin) is the reference
for loopback CDP skinning, the Dream Skin theme package format, and the distinction
between the Windows Codex desktop executable and CLI. SkinStudio does not bundle
its injector, Node runtime, installer or source files. Its new Codex adapter is an
independent wallpaper and color-token implementation; it does not implement all
of Dream Skin's layout-specific effects.

The built-in Aurora wallpaper is the original project's procedural image.
Downloaded themes retain their own authorship and licenses in their metadata.
The online theme library is a third-party service at dreamskin.cc / api.dreamskin.cc.

The executable is built using [ps2exe](https://github.com/MScholtes/PS2EXE).
No official ZCode, MonkeyCode, Codex, ChatGPT, OpenCode or WorkBuddy application binaries are included.

[OpenCode](https://github.com/anomalyco/opencode) is the reference for the desktop
theme preference and UI token names. The adapter is independently implemented;
no OpenCode runtime or source files are bundled. Terminal theme JSON configuration
is separate from the Electron desktop wallpaper adapter.

[workbuddy-skin](https://github.com/itcastWsy/workbuddy-skin) (MIT) was consulted
for WorkBuddy desktop startup environment variables and renderer architecture.
SkinStudio independently implements its WorkBuddy adapter; no injector, scripts,
wallpapers or official WorkBuddy source/binaries from that project are bundled.
