# SteamPipe templates (manual upload)

No secrets, no SDK files. Replace `APPID` / `DEPOT_*` with the real IDs from
Steamworks, export both presets (see `export_presets.cfg` or the
`towerdef-pc export` workflow) into `build/towerdef-pc-0001/{windows,linux}`,
then run from a machine with steamcmd:

    steamcmd +login <builder> +run_app_build $(pwd)/app_build.vdf +quit

Steam Auto-Cloud: configure root `WinAppDataRoaming` / `LinuxXdgDataHome`,
subdir `Godot/app_userdata/Corehold-PC` (custom user dir `Corehold-PC`),
patterns `slot_*.json` and `settings.cfg`.

The game itself only talks to Steam through `SteamService.gd`, which no-ops
unless the GodotSteam GDExtension is installed and an App ID is present
(`steam_appid.txt` next to the executable in dev — never commit it).
