# Veil - Project Memory

> **For AI Assistants:** This file contains the complete project context, lessons, and patterns for Veil. Load this first to understand the codebase.

---

## Project Overview

**Veil** is a universal V Rising mod UI framework that supports multiple mods via manifest-based adapters. It creates its own independent Canvas overlay, not hooked to the game's UI system.

| Property | Value |
|----------|-------|
| **Name** | Veil |
| **Author** | DiNaSoR |
| **GUID** | `com.dinasor.veil` |
| **Version** | 0.1.0 |
| **License** | MIT |
| **Framework** | BepInEx 6 + IL2CPP |
| **Target** | V Rising (Unity 2022.3) |

---

## Architecture

```
Veil/
├── Plugin.cs                 # BepInEx entry point
├── Core/
│   ├── VeilCore.cs           # Main initialization orchestrator
│   ├── CanvasManager.cs      # Independent ScreenSpaceOverlay canvas
│   ├── AdapterManager.cs     # Discovers and loads adapter manifests
│   ├── AssetLoader.cs        # Loads assets from adapter folders
│   ├── UIOrchestrator.cs     # Manages UI component lifecycle
│   └── UIComponentFactory.cs # Creates components from manifest definitions
├── UI/
│   ├── Interfaces/
│   │   └── IUIComponent.cs   # Component contract
│   └── Components/
│       ├── UIComponentBase.cs # Abstract base with common functionality
│       ├── Label.cs          # Text display
│       ├── ProgressBar.cs    # XP/health bar with fill
│       ├── Panel.cs          # Container for children
│       └── Button.cs         # Clickable with action
├── Adapters/
│   ├── Models/
│   │   ├── Adapter.cs        # Adapter container
│   │   └── Manifest.cs       # JSON manifest structure
│   └── YourMod/              # Your adapter folder
│       └── manifest.json
├── Data/
│   ├── DataBinding.cs        # Connects UI to data sources
│   ├── CommandBridge.cs      # Sends chat commands
│   └── ResponseParser.cs     # Regex parsing of responses
├── Patches/
│   ├── InputPatch.cs         # F1/F2/F3 key handling via Harmony
│   └── ChatPatches.cs        # Chat command/response interception
├── Persistence/
│   ├── LayoutService.cs      # Saves/loads UI positions
│   └── DraggableElement.cs   # Drag-and-drop behavior
└── Services/
    ├── Log.cs                # Central logging wrapper
    └── DebugBridge.cs        # VDebug integration (optional)
```

---

## Controls

| Key | Action |
|-----|--------|
| **F1** | Toggle UI visibility |
| **F2** | Dump status to console |
| **F3** | Force show UI |
| **F4** | Test key (verifies input works) |

---

## Key Design Decisions

### 1. Independent Canvas (Not Game Hooked)
**Why:** The game's `UICanvasSystem` hook was unreliable. We create our own `ScreenSpaceOverlay` canvas with high sort order (1000) for guaranteed visibility.

```csharp
_canvas = canvasGo.AddComponent<Canvas>();
_canvas.renderMode = RenderMode.ScreenSpaceOverlay;
_canvas.sortingOrder = 1000;
```

### 2. Manifest-Driven Adapters
**Why:** Zero code changes needed for mod authors. Just create a `manifest.json`.

### 3. Harmony Patch for Input (Not MonoBehaviour.Update)
**Why:** IL2CPP doesn't reliably call `MonoBehaviour.Update()` on injected types. We patch `UICanvasSystem.UpdateHideIfDisabled` which runs every frame.

### 4. VDebug Integration
**Why:** Optional logging to VDebug console if installed, falls back to BepInEx logging.

---

## IL2CPP Lessons (CRITICAL - DO NOT VIOLATE)

### L-004 — Avoid RectOffset 4-arg constructor
```csharp
// WRONG - will crash in IL2CPP
new RectOffset(left, right, top, bottom);

// CORRECT
RectOffset padding = new();
padding.left = 10;
padding.right = 10;
padding.top = 5;
padding.bottom = 5;
```

### L-005 — Qualify Object.Destroy
```csharp
// WRONG - ambiguous
Object.Destroy(gameObject);

// CORRECT
UnityEngine.Object.Destroy(gameObject);
```

### L-015 — AddComponent requires type injection
```csharp
// In static constructor of your MonoBehaviour:
static MyComponent()
{
    ClassInjector.RegisterTypeInIl2Cpp<MyComponent>();
}

public MyComponent(IntPtr ptr) : base(ptr) { }
```

### L-017 — Optional plugin integration via reflection
```csharp
// WRONG - may not exist
Chainloader.PluginInfos["other.plugin"];

// CORRECT - discover via reflection
var assembly = AppDomain.CurrentDomain.GetAssemblies()
    .FirstOrDefault(a => a.GetName().Name == "OtherPlugin");
if (assembly != null)
{
    var apiType = assembly.GetType("OtherPlugin.Api");
    // invoke methods via reflection
}
```

### L-021 — Unity "destroyed == null" behavior
```csharp
// WRONG - _initialized stays true even after Unity destroys the object
if (_initialized) return;

// CORRECT - check actual object existence
if (_canvas != null && _hudRoot != null) return;
```

---

## UI Lessons

### L-001 — Bind by slot ID, not name
Actions should use stable slot/ID identifiers, not display names which can collide.

### L-002 — Hide missing sprites (no placeholders)
If sprite lookup fails, hide the icon element instead of showing a white box.

### L-008 — Non-interactive TMP text must not block raycasts
```csharp
textComponent.raycastTarget = false;
```

### L-018 — Layout drag must use canvas-local coordinates
Use `RectTransformUtility.ScreenPointToLocalPointInRectangle` with the root canvas camera.

### L-019 — Handle zero-size root rects
Fall back to child `RectTransform` bounds when the root rect has no size.

---

## Adapter Manifest Structure

```json
{
  "id": "modname",
  "displayName": "Mod Display Name",
  "version": "1.0.0",
  "targetMod": "OriginalMod",
  "detection": {
    "chatPrefix": ".modcmd"
  },
  "hud": {
    "elements": [
      {
        "id": "unique-id",
        "type": "progressBar|label|panel|button",
        "position": { "x": 100, "y": 100 },
        "size": { "width": 200, "height": 30 },
        "draggable": true,
        "dataSource": {
          "command": ".xp",
          "responsePattern": "Level (\\d+) \\[(\\d+)/(\\d+)\\]",
          "refreshInterval": 30
        }
      }
    ]
  }
}
```

---

## Data Flow

```
1. AdapterManager discovers manifest.json files in Adapters/
2. UIComponentFactory creates components from element definitions
3. UIOrchestrator manages component lifecycle
4. CanvasManager provides the root Canvas
5. DataBinding auto-refreshes by sending chat commands
6. ResponseParser extracts values via regex
7. Components update their display
```

---

## File Locations at Runtime

| Path | Purpose |
|------|---------|
| `BepInEx/plugins/Veil.dll` | Main plugin |
| `BepInEx/plugins/Adapters/` | Adapter folders with manifest.json |
| `BepInEx/plugins/Layouts/` | Saved UI positions |

---

## Engineering Rules (from .cursor/rules)

1. **Reason about existing codebase first** before writing new code
2. **Preserve modular architecture** - no monolithic logic
3. **Reuse existing utilities** - don't duplicate
4. **No new global state/singletons** without established pattern
5. **Small reviewable changes** over large refactors

---

## Build Lessons

### L-009 — Post-build targets must not break builds
- Use `$(TargetPath)` not `$(ProjectName).dll`
- Guard optional post-build steps with conditions
- Deploy copies should use `ContinueOnError="true"`

### L-010 — `dotnet build -t:Compile` doesn't create `bin/` outputs
Use `dotnet build` (default target), not `-t:Compile`.

### L-016 — MyPluginInfo namespace matches RootNamespace
Set `<RootNamespace>` in csproj to match where you reference `MyPluginInfo`.

---

## History

| Event | Date |
|-------|------|
| VRiseUI created | 2026-01-17 |
| Renamed to Veil | 2026-01-19 |
| Switched to independent canvas | 2026-01-18 |
| Input moved to Harmony patch | 2026-01-18 |

---

## Credits

- **DiNaSoR** - Creator of Veil
- **V Rising Modding Community**
