# Graph Report - SkyPaste  (2026-05-20)

## Corpus Check
- 51 files · ~262,745 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 528 nodes · 743 edges · 46 communities (27 shown, 19 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 25 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `299b81d9`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Swift Protocols & Data Types|Swift Protocols & Data Types]]
- [[_COMMUNITY_Storage & Persistence Layer|Storage & Persistence Layer]]
- [[_COMMUNITY_Media Processing Pipeline|Media Processing Pipeline]]
- [[_COMMUNITY_Clipboard Monitoring Engine|Clipboard Monitoring Engine]]
- [[_COMMUNITY_App Lifecycle & Delegate|App Lifecycle & Delegate]]
- [[_COMMUNITY_Hotkey & Window Management|Hotkey & Window Management]]
- [[_COMMUNITY_Clipboard Item Row UI|Clipboard Item Row UI]]
- [[_COMMUNITY_Emoji Picker Component|Emoji Picker Component]]
- [[_COMMUNITY_Kilo Agent Session Tracking|Kilo Agent Session Tracking]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Thumbnail Generation|Thumbnail Generation]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Welcome & Onboarding View|Welcome & Onboarding View]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Build System & Packaging|Build System & Packaging]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Image Caching System|Image Caching System]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Kilo Package Dependencies|Kilo Package Dependencies]]
- [[_COMMUNITY_Privacy & Compliance Policies|Privacy & Compliance Policies]]
- [[_COMMUNITY_Adaptive Polling & Battery|Adaptive Polling & Battery]]
- [[_COMMUNITY_Main Screen Screenshots|Main Screen Screenshots]]
- [[_COMMUNITY_Shortcuts Screen Screenshots|Shortcuts Screen Screenshots]]
- [[_COMMUNITY_Agent Manager Configuration|Agent Manager Configuration]]
- [[_COMMUNITY_Folders Screen Screenshots|Folders Screen Screenshots]]
- [[_COMMUNITY_Settings Screen Screenshots|Settings Screen Screenshots]]
- [[_COMMUNITY_UI Display Patterns|UI Display Patterns]]
- [[_COMMUNITY_KiloCode Plugin Config|KiloCode Plugin Config]]
- [[_COMMUNITY_Item Type Enumeration|Item Type Enumeration]]
- [[_COMMUNITY_Floating Panel Implementation|Floating Panel Implementation]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]

## God Nodes (most connected - your core abstractions)
1. `Storage` - 43 edges
2. `AppDelegate` - 34 edges
3. `ClipboardMonitor` - 27 edges
4. `ClipboardItemRow` - 26 edges
5. `FloatingPanel` - 16 edges
6. `EmojiNSButton` - 16 edges
7. `PreferencesView` - 15 edges
8. `UpdateChecker` - 14 edges
9. `ShortcutRecorder` - 14 edges
10. `CodingKeys` - 12 edges

## Surprising Connections (you probably didn't know these)
- `Storage (excellent-cloud)` --semantically_similar_to--> `Storage`  [INFERRED] [semantically similar]
  .kilo/worktrees/excellent-cloud/Sources/Storage.swift → Sources/Storage.swift
- `ClipboardMonitor (excellent-cloud)` --semantically_similar_to--> `ClipboardMonitor`  [INFERRED] [semantically similar]
  .kilo/worktrees/excellent-cloud/Sources/ClipboardMonitor.swift → Sources/ClipboardMonitor.swift
- `ClipboardItem (excellent-cloud)` --semantically_similar_to--> `ClipboardItem`  [INFERRED] [semantically similar]
  .kilo/worktrees/excellent-cloud/Sources/Models.swift → Sources/Models.swift
- `Image Support` --semantically_similar_to--> `Thumbnail Generation`  [INFERRED] [semantically similar]
  README.md → clipboard_media_task.md
- `Global Shortcuts` --semantically_similar_to--> `Keyboard Input Access`  [INFERRED] [semantically similar]
  README.md → PRIVACY_POLICY.md

## Hyperedges (group relationships)
- **Build Process Flow** — build_sh_homebrew_swift_toolchain, build_sh_swift_build, build_sh_app_bundle_creation, build_sh_info_plist_generation, build_sh_codesigning [EXTRACTED 1.00]
- **Privacy Compliance Framework** — privacy_policy_md_gdpr_compliance, privacy_policy_md_ccpa_compliance, privacy_policy_md_pipeda_compliance, privacy_policy_md_local_first_architecture [EXTRACTED 1.00]
- **Clipboard Media Capture Pipeline** — clipboard_media_task_md_thumbnail_generation, clipboard_media_task_md_file_type_matrix, clipboard_media_task_md_operation_queue_concurrency, clipboard_media_task_md_memory_limit_during_capture, clipboard_media_task_md_file_metadata_storage [EXTRACTED 1.00]
- **Clipboard Processing Pipeline** — sources_clipboardmonitor_clipboardmonitor, sources_storage_storage, sources_imagecache_imagecache, sources_thumbnailgenerator_thumbnailgenerator [EXTRACTED 1.00]
- **Hotkey-to-Window Display Flow** — sources_hotkeymanager_hotkeymanager, sources_hotkeymanager_windowmanager, sources_hotkeymanager_floatingpanel, sources_app_appdelegate [EXTRACTED 1.00]
- **App Initialization Sequence** — sources_app_appdelegate, sources_storage_storage, sources_clipboardmonitor_clipboardmonitor, sources_hotkeymanager_hotkeymanager, sources_updatechecker_updatechecker [EXTRACTED 1.00]
- **Preferences Tab Components** — ui_storagetabview_storagetabview, ui_folderstabview_folderstabview, ui_abouttabview_abouttabview, ui_shortcutrecorder_shortcutrecorder [EXTRACTED 1.00]
- **Folder Management Views** — ui_folderstabview_folderstabview, ui_foldereditview_foldereditview, ui_mainview_folderoverlay [INFERRED 0.85]
- **Shortcut Recording Pattern** — ui_shortcutrecorder_shortcutrecorder, ui_clipboarditemrow_formatshortcut, ui_shortcutrecorder_formatshortcut [INFERRED 0.75]

## Communities (46 total, 19 thin omitted)

### Community 0 - "Swift Protocols & Data Types"
Cohesion: 0.06
Nodes (38): Auto-Update Mechanism, CaseIterable, Codable, CodingKey, Equatable, Hashable, Identifiable, ObservableObject (+30 more)

### Community 2 - "Media Processing Pipeline"
Cohesion: 0.07
Nodes (29): AVAssetImageGenerator, Disk Cache Cleanup, File Metadata Storage, File Type Matrix, GIF Animation Handling, LRU Cache Eviction, Memory Limit During Capture, Operation Queue Concurrency (+21 more)

### Community 3 - "Clipboard Monitoring Engine"
Cohesion: 0.14
Nodes (6): Clipboard Monitoring, Image Processing Pipeline, NSObject, NSPasteboardItemDataProvider, ClipboardMonitor, ImagePasteboardProvider

### Community 4 - "App Lifecycle & Delegate"
Cohesion: 0.14
Nodes (6): App, App Lifecycle Management, NSApplicationDelegate, AppDelegate, SkyPasteApp, UNUserNotificationCenterDelegate

### Community 5 - "Hotkey & Window Management"
Cohesion: 0.10
Nodes (15): Floating Window Management, Global Hotkey System, NSHostingView<Content>, NSPanel, NSWindowDelegate, AdaptiveHostingView, carbonModifiers(), FloatingPanel (+7 more)

### Community 7 - "Emoji Picker Component"
Cohesion: 0.06
Nodes (13): NSButton, NSColorWell, NSTextInputClient, NSViewRepresentable, Coordinator, EmojiNSButton, EmojiPickerButton, FixedColorWell (+5 more)

### Community 8 - "Kilo Agent Session Tracking"
Cohesion: 0.13
Nodes (14): createdAt, worktreeId, sessions, ses_1c73076e4ffe0NipQSD1q08mtN, tabOrder, local, worktreeOrder, worktrees (+6 more)

### Community 9 - "Community 9"
Cohesion: 0.22
Nodes (3): formatShortcut(), formatShortcut(), ShortcutRecorder

### Community 10 - "Thumbnail Generation"
Cohesion: 0.21
Nodes (7): Sendable, ThumbnailGenerator, ThumbStatus, failed, ok, pending, Thumbnail Generation

### Community 11 - "Community 11"
Cohesion: 0.18
Nodes (5): Animation, Date, SMAppService, View, VisualEffectView

### Community 12 - "Welcome & Onboarding View"
Cohesion: 0.21
Nodes (5): FeatureRow, OnboardingStep, shortcuts, welcome, WelcomeView

### Community 13 - "Community 13"
Cohesion: 0.10
Nodes (15): DropDelegate, FloatingPanel, PreferenceKey, FolderRowHeightPreferenceKey, LibraryContentView, LibraryDropDelegate, LibraryFolderRow, LibraryOverlay (+7 more)

### Community 15 - "Build System & Packaging"
Cohesion: 0.22
Nodes (9): App Bundle Creation, Code Signing, Homebrew Swift Toolchain, Info.plist Generation, Swift Build, App Bundle Creation (worktree), SkyPaste Package (worktree), macOS 14.0+ Target (+1 more)

### Community 16 - "Community 16"
Cohesion: 0.32
Nodes (3): FoldersTabView, checkForDuplicate(), saveFolderShortcuts()

### Community 18 - "Community 18"
Cohesion: 0.36
Nodes (5): FoldersTabWrapper, GeneralTabView, ShortcutsSection, ShortcutsTabView, View

### Community 21 - "Privacy & Compliance Policies"
Cohesion: 0.67
Nodes (3): CCPA Compliance, GDPR Compliance, PIPEDA Compliance

### Community 36 - "Community 36"
Cohesion: 0.11
Nodes (17): Accessibility & Permissions, 🔒 All Data Stays Local, Changes to This Policy, Compliance, Contact & Questions, 🎯 Data Control, 💾 How Data is Stored, Key Privacy Principles (+9 more)

### Community 37 - "Community 37"
Cohesion: 0.11
Nodes (17): Accessibility & Permissions, 🔒 All Data Stays Local, Changes to This Policy, Compliance, Contact & Questions, 🎯 Data Control, 💾 How Data is Stored, Key Privacy Principles (+9 more)

### Community 38 - "Community 38"
Cohesion: 0.13
Nodes (14): 🔴 P1 — Критично, 🟡 P2 — Важно, 🟢 P3 — Желательно, UI: не показывать все превью сразу, Анимация / GIF: показывать статичный первый кадр, Главный принцип, Задача: обработка медиа и файлов в буфере обмена (macOS), Захват thumbnail в момент копирования, не при показе (+6 more)

### Community 39 - "Community 39"
Cohesion: 0.29
Nodes (6): Features, Installation, Privacy, Settings, SkyPaste 📋, Support & Feedback

### Community 40 - "Community 40"
Cohesion: 0.18
Nodes (10): Features, Global Shortcuts, In-App Shortcuts (when SkyPaste window is open), Installation, Keyboard Shortcuts, Preview Panel Shortcuts (hover over an item to see preview), Privacy, Settings (+2 more)

### Community 41 - "Community 41"
Cohesion: 0.36
Nodes (9): AppDelegate (excellent-cloud), SkyPasteApp (excellent-cloud), ClipboardMonitor (excellent-cloud), HotkeyManager (excellent-cloud), WindowManager (excellent-cloud), ImageCache (excellent-cloud), ClipboardItem (excellent-cloud), Storage (excellent-cloud) (+1 more)

## Knowledge Gaps
- **146 isolated node(s):** `@kilocode/plugin`, `branch`, `path`, `parentBranch`, `createdAt` (+141 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **19 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AppDelegate` connect `App Lifecycle & Delegate` to `Swift Protocols & Data Types`, `Storage & Persistence Layer`, `Clipboard Monitoring Engine`, `Hotkey & Window Management`, `Image Caching System`?**
  _High betweenness centrality (0.164) - this node is a cross-community bridge._
- **Why does `EmojiPickerButton` connect `Emoji Picker Component` to `Community 16`, `Community 19`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Why does `Storage` connect `Storage & Persistence Layer` to `Swift Protocols & Data Types`, `Clipboard Monitoring Engine`, `App Lifecycle & Delegate`, `Hotkey & Window Management`, `Community 41`, `Image Caching System`?**
  _High betweenness centrality (0.124) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `Storage` (e.g. with `JSON-based Persistence` and `Storage (excellent-cloud)`) actually correct?**
  _`Storage` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `AppDelegate` (e.g. with `App Lifecycle Management` and `AppDelegate`) actually correct?**
  _`AppDelegate` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `ClipboardMonitor` (e.g. with `ImagePasteboardProvider` and `Clipboard Monitoring`) actually correct?**
  _`ClipboardMonitor` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `@kilocode/plugin`, `branch`, `path` to the rest of the system?**
  _146 weakly-connected nodes found - possible documentation gaps or missing edges._