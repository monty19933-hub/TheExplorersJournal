# The Explorer's Journal

The Explorer's Journal is a World of Warcraft Classic Era addon scaffold for route-based exploration overlays.

It provides:

- A draggable `/tej` journal window with selectable routes.
- A draggable HUD overlay with a 2D route panel, player marker, next waypoint, and compass direction.
- A world map route overlay with start/end markers and connected path lines.
- Numbered world map and minimap route markers with connected path lines.
- Cross-zone routes where each waypoint can declare its own `mapID`.
- Expandable route difficulty sections: Easy, Intermediate, and Advanced.
- Expandable continent sections: Eastern Kingdoms and Kalimdor.
- Scrollable waypoint notes under the selected route.
- Hover tooltips for difficulty sections and waypoint instructions.
- Hover tooltips on numbered world map and minimap route markers.
- A draggable minimap button with a scroll icon for opening the journal.
- The journal closes with Esc like a standard WoW panel.
- In-game custom route creation with continent and difficulty selection.
- GPS waypoint capture for custom routes with label and instruction notes.
- Right-click deletion for custom route waypoints, with confirmation.
- Right-click deletion for custom routes, with confirmation.
- Route-level Items and Spells needed list with icons and tooltips.
- Item/Spell add dialog has an explicit Item ID or Spell ID mode.
- Saved custom routes captured in-game with slash commands.
- A simple `Data.lua` file where you can add permanent route definitions.
- Built-in routes can be adapted from credited video or written guides, then refined with GPS waypoints in-game.

## Install

Copy the `TheExplorersJournal` folder into:

```text
World of Warcraft\_classic_era_\Interface\AddOns\
```

Restart the game or run `/reload`, then enable **The Explorer's Journal** from the AddOns screen.

The TOC currently targets Classic Era interface `11507`, which corresponds to the 1.15.7 client family. If your client marks it out of date after a patch, run this in-game:

```text
/dump (select(4, GetBuildInfo()))
```

Then update `## Interface:` in `TheExplorersJournal.toc` with that number.

## Commands

```text
/tej
```

Open or close the journal.

```text
/tej pos
```

Print your current map ID and coordinates.

```text
/tej add <label>
```

Add your current position to a saved custom route for the current map.

```text
/tej export
```

Print the active route as Lua data so you can paste it into `Data.lua`.

```text
/tej hud
```

Toggle the route overlay.

```text
/tej map
```

Toggle the world map path overlay.

```text
/tej minimap
```

Toggle the minimap path guide.

```text
/tej openmap
```

Open the selected route's zone map when the client API supports it.

```text
/tej status
```

Print route, player map, world map, and overlay diagnostics.

## Adding Permanent Routes

Add routes to `TheExplorersJournal/Data.lua`:

```lua
{
    id = "my-route-id",
    name = "My Route Name",
    category = "Hidden Areas",
    continent = "eastern-kingdoms",
    difficulty = "easy",
    mapID = 1426,
    description = "Short note about the path.",
    waypoints = {
        { mapID = 1426, x = 0.427, y = 0.404, label = "Starting point", note = "What to do here." },
        { mapID = 1426, x = 0.405, y = 0.382, label = "Next climb", note = "What to do next." },
        { mapID = 1426, x = 0.377, y = 0.356, label = "Ridge", note = "Final instruction." },
    },
}
```

WoW addons cannot draw true 3D lines in the game world. This addon uses UI overlays and map coordinates instead, so routes work best when you capture enough waypoints to make the path obvious.

The world map overlay is exact for the selected route's zone map. The minimap overlay is a relative guide centered on the player; it is useful for following nearby segments, but it is not a replacement for Blizzard's internal minimap coordinate projection.
