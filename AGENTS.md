# AGENTS.md

Repository memory for Psych Engine Mint (Android-focused fork of Psych Engine 1.0.4).

## Layout

- `source/backend/` – core engine classes (`MusicBeatState`, `MusicBeatSubstate`, `Controls`, `ClientPrefs`, `Paths`, `Mods`, ...).
- `source/states/`, `source/substates/`, `source/options/`, `source/objects/` – gameplay states, menus and option menus.
- `source/mobile/` – Android/mobile layer ported from `CarGamerYouTuber/FNF-PsychEngine-Mobile`:
  - `backend/` (`MobileData`, `MobileScaleMode`, `StorageUtil`, `TouchFunctions`, `PsychJNI`),
  - `input/` (`MobileInputID`, `MobileInputManager`),
  - `objects/` (`TouchPad`, `TouchButton`, `Hitbox`, `MobileControls`, `IMobileControls`),
  - `substates/MobileControlSelectSubState`, `options/MobileOptionsSubState`, `psychlua/MobileFunctions`.
- `source/psychlua/*` are one-line typedef shims pointing at `source/scripting/lua/*`.
- Mobile assets live in `assets/shared/mobile/` (`images/touchpad/*`, `DPadModes/*.json`, `ActionModes/*.json`) and `assets/exclude/mobile/`.
- Indentation is tabs; mobile sources were normalised to tabs on import.
- Game data (assets, mods, saves, crash logs) lives in `/storage/emulated/0/.PsychEngineMint/` on Android: `Main`
  sets the cwd from `StorageUtil.getStorageDirectory()` and falls back to `Context.getExternalFilesDir()` when the
  external folder is not writable. `EXTERNAL_DATA` is no longer offered; legacy values map to `EXTERNAL`.
  `StorageUtil.copyContents()` moves data between storage types before the old folder is removed.
- `assets/base_game/` (weeks, charts, characters, stages, songs) is packaged under the `assets/` id through the
  `BASE_GAME_FILES` define in `Project.xml`; without that define story mode and freeplay have no weeks at all.
- `StorageUtil.setupGameDirectory()` (called from `Main`) creates `<game folder>/assets|mods|saves|crash|logs|backups`
  and copies the packaged text data (json/txt/xml/frag/vert/lua) out of the APK. Media (png/jpg/ogg/mp3/mp4/...) is
  deliberately **not** copied: `Paths` reads it from the package through `openfl.utils.Assets`. `.assets_extracted`
  stores the app version and is only written when every file was copied, so a partial extraction retries.

## Build

`Project.xml` already carries the Android config (SDK 24/36, ARM64 only, permissions, `extension-androidtools`, `lime` 8.x). The mobile layer itself needs no `Project.xml` change; `mobile` is defined by lime for android/ios targets.

## Typechecking without the Android SDK

A full hxcpp build needs the Android NDK, but Haxe can typecheck the graph on the `neko` target:

```bash
haxe -cp source -lib flixel -lib flixel-addons -lib tjson -lib flixel-animate \
     -D MODS_ALLOWED -D BASE_GAME_FILES -D TRANSLATIONS_ALLOWED -D MULTITHREADED_LOADING -D mobile \
     --macro "backend.macro.Init.init()" -neko --no-output -main Main
```

- `--macro backend.macro.Init.init()` is mandatory (it comes from `haxeflag` in `Project.xml`); without it the
  scripting macro never runs and `Note.extraData` is reported as a missing field.
- `MULTITHREADED_LOADING` is on in `Project.xml`; without it `LoadingState.getCPUThreadsCount()` (compiled only for
  `cpp`/`hl`) is unknown.
- `linc_luajit`, `hscript-insanity`, `funkin.vis` and `hxvlc` are not on haxelib, so leave `LUA_ALLOWED`,
  `HSCRIPT_ALLOWED`, `VIDEOS_ALLOWED` off to typecheck the rest of the graph.

Expect noise from target-specific APIs (`FlxG.save`, `FlxG.sound`, `FlxG.mouse`, `FlxG.keys`, `FlxG.gamepads`, `Sound.fromFile`, `cpp.Callable`, `openfl.media.Sound` vs `flash.media.Sound`, `FileFilter`) because flixel/openfl disable or alias those on `neko`; ignore those and look for "Type not found" / "has no field" errors on project types. `-D flixel_animate` is unnecessary: the define is `flixel_animate` and it comes from the `flixel-animate` haxelib.

## Mobile conventions

- Touch code must stay inside `#if mobile` (or `#if android` for BACK/MENU/JNI) so desktop builds keep compiling and behave unchanged.
- Input plumbing: `Controls.mobileBinds` → `MusicBeatSubstate.mobileControls`/`touchPad` → `PlayStateInput.mobileBinds` for hitboxes.
  `Controls.getInputTarget()` returns the deepest open `MusicBeatSubstate` that owns a pad, so a sub menu without one
  does not swallow the input of the menu behind it.
- `MobileData.init()` must run once before `MobileData.mode`/`dpadModes`/`actionModes` are used. It is guarded and
  called from both `TitleState` and `MusicBeatSubstate.addTouchPad()`, because `FlashingState` is created first.
- Any state that reads `controls.UI_*`/`ACCEPT`/`BACK` needs its own `addTouchPad(dpad, action)`; the main menu is the
  exception and is navigated by tapping the icons (it must stay free of A/B/LEFT/RIGHT buttons).
- Use `Paths.exists(path)` instead of `FileSystem.exists(path)` when deciding whether an asset exists: on Android the
  data may only live inside the APK. `Paths.getTextFromFile()`/`Paths.returnSound()` already fall back to
  `openfl.utils.Assets`, which is the only read path that works for media.
- `TouchButton.checkTouchOverlap()` must only report an overlap when a touch actually lands on the button, otherwise
  the button never receives its release event and looks dead.
- `ClientPrefs.data.wideScreen` defaults to false so `MobileScaleMode` letterboxes/pillarboxes; the "Wide Screen Mode"
  option still stretches for users who enable it. `settingsVersion` migrates old saves that carried the stretch default.
- `MobileControlSelectSubState` declares its reset button as `resetBtn`; `reset()` is already a method on `MusicBeatSubstate`, so a field named `reset` will not compile.
