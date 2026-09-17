# QFXMythicTalents

QFXMythicTalents is a World of Warcraft addon that shows Mythic+ dungeon and
raid boss talent recommendations on the Blizzard talent frame, with one-click
apply and a personal loadout list.

## Features

- Dungeon and raid boss recommendations for the current specialization
- One-click apply through Blizzard's native loadout importer
- Node choice rates computed from compact pre-collected sample data
- Personal loadouts (save / load / rename / delete / reorder) per specialization
- Personal loadouts apply through the same native importer, and auto-generated
  recommendation loadouts are pruned so the loadout list never accumulates them
- Optional EllesmereUI skin: themed window and widgets, selection highlight in
  the user's accent color

## Requirements

- World of Warcraft Retail (Interface 120007, 120100)
- The `QFXTalentData` data addon and its per-content data packages

## Contents

- `QFXMythicTalents/` - the addon itself (TOC, Lua sources, dev tools in `tools/`)

## Notes

The repository excludes local backups, release archives and the packed-data
build workspace; those live outside version control on the development machine.
