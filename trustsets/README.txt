TRUSTSETS v1.5.1 — Corrected FFXI Window Type Themes
Author: Dugahst | Final Fantasy XI | Ashita v4
=======================================================

INSTALLATION / UPGRADE
----------------------
1. Extract this ZIP into your Ashita/addons/ directory.
   Keep the entire trustsets folder and all included theme assets:

     Ashita/addons/trustsets/trustsets.lua
     Ashita/addons/trustsets/window_themes.lua
     Ashita/addons/trustsets/assets/themes/14/ ... 21/

2. Do NOT remove your previous config/addons/trustsets folder: saved
   Trust presets and cast delay are stored in character-specific settings.
3. Use /addon reload trustsets (or /addon load trustsets if unloaded).
4. Open the GUI using /tsets or /trustsets.

WHAT'S NEW: THEMES
------------------
- TrustSets > Settings > Themes contains nine choices:
    Olympus XI (default)
    Window Type 1 (FFXI ROM/0/14.DAT)
    Window Type 2 (FFXI ROM/0/15.DAT)
    Window Type 3 (FFXI ROM/0/16.DAT)
    Window Type 4 (FFXI ROM/0/17.DAT)
    Window Type 5 (FFXI ROM/0/18.DAT)
    Window Type 6 (FFXI ROM/0/19.DAT)
    Window Type 7 (FFXI ROM/0/20.DAT)
    Window Type 8 (FFXI ROM/0/21.DAT)
- The eight window styles use background, horizontal/vertical border,
  and corner graphics EXTRACTED FROM THE USER-PROVIDED DAT ARCHIVE.
- Backgrounds are tiled at the full native 128x128 DAT resolution.
  No stretching or artificial 96px row cropping.
- All eight styles have been tuned against in-game chat screenshots.
  The heavy dark overlay and opaque content panels from v1.5.0 have
  been removed. Style 5 retains translucency; the others preserve their
  characteristic FFXI patterns and color balance.
- Theme changes apply to the TrustSets window and save automatically
  in the same character-specific settings as the Trust sets.
- Game DATs are NOT overwritten, altered, or required at runtime.
- If a Direct3D texture cannot load, the themed window reverts to
  the classic Olympus palette rather than preventing use of the addon.

COMMANDS
--------
 /tsets, /trustsets          Show/hide TrustSets GUI
 /tsets settings            Open the Settings tab
 /tsets themes              Open Settings > Themes
 /tsets open | close        Show/hide GUI explicitly
 /tset theme                Show selected theme
 /tset theme olympus        Use original Olympus XI style
 /tset theme 1             Select Window Type 1 (1-8 supported)
 /tset list                 List presets
 /tset show NAME            Show a preset
 /tset add NAME A, B, C     Create or update a preset (up to 5)
 /tset capture [NAME]       Save active Trusts to a new preset
 /tset delete NAME          Delete preset
 /tset run NAME             Summon preset, keep current Trusts
 /tset replace NAME         Dismiss and replace with preset
 /tset stop                 Stop the summon queue and retries
 /tset release              Dismiss all Trusts
 /tset status               Show current queue and retry state
 /tset delay [4|5|6|7]      Inspect or change summon delay
 /tset help                 Display command help

Aliases: /tset gui, /tset ui, /tset panel; /tset summon NAME;
/tset switch NAME; /tset save NAME A, B; /tset current NAME;
/tset remove NAME; /tset cancel.

STILL INCLUDED FROM v1.4.9
-------------------------
- Up to five members per saved party, with order control.
- Captures currently active Trusts; multiword name correction.
- Summon verification and up to 3 total attempts per member.
- Cast delay of 4/5/6/7 seconds, saved per character.
- Hidden-on-startup behavior; TrustSets authored by Dugahst.
- Olympus XI gold corner ornaments, when using Olympus theme.
- Original mouse handling; no experimental interception changes.

LIMITATIONS / TESTING
---------------------
- Static checks and simulation tests completed locally.
- Direct3D texture output and the live client have not been tested in
  a running FFXI client; colors and border treatment may vary.
- Some alternate Trust versions cannot be uniquely detected by party
  name (for example, Shantotto versus Shantotto II).
- Trust summoning is subject to in-game restrictions.

WHAT CHANGED IN v1.5.1
-----------------------
- Corrected colors using the eight user-provided game/chat comparisons.
- Removed stacked dark overlays that hid the real FFXI window texture.
- Corrected full 128x128 DAT background tiling.
- Aligned the 16x16 source quadrants for each decorative corner.
- Improved theme-matched form input colors, preserving contrast.
- All saved presets, settings and casting/retry logic are unchanged.
- No live-game verification possible here; preview with /tsets.
