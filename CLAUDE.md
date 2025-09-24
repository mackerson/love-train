# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Love Train is a train simulation game built with Love2D (Lua game framework) where players can draw railway tracks and watch trains navigate them. Trains spawn from a depot, follow player-drawn tracks, and automatically return along their path when encountering obstacles.

## Running the Game

```bash
love .
```

Requires Love2D to be installed.

## Architecture

The codebase follows an object-oriented architecture using a custom class system (`lib/base-class.lua`). Main components:

- **Entity/System Architecture**: Entities (`entities/`) contain game objects, Systems (`systems/`) handle logic
- **Main Game Loop**: `main.lua` coordinates all systems and handles input/rendering
- **Class System**: All classes inherit from `base-class.lua` using `extend()` and `new()` patterns

### Key Systems

- **TrackManager** (`systems/track-manager.lua`): Manages track placement/removal with grid snapping and connection logic
- **Camera** (`systems/camera.lua`): Handles viewport transformation and zoom
- **DebugLog** (`systems/debug-log.lua`): Scrollable log panel for train activity
- **Pathfinder** (`lib/pathfinder.lua`): A* pathfinding for train navigation

### Key Entities

- **Train** (`entities/train.lua`): Train behavior, collision detection, state management
- **Track** (`entities/track.lua`): Individual track segments with connection points
- **Depot** (`entities/depot.lua`): Train spawn point and return destination

## Game State Management

- **Position Tracking**: Hash map (`occupied_positions`) tracks train positions for collision detection using "x_y" keys
- **Train States**: `moving`, `stopped`, `off_track` with interpolation for smooth movement
- **Track Connections**: Automatic connection to nearby tracks within range

## Input Handling

- Mouse drag for track placement with debouncing
- Camera follows mouse movement
- Zoom via mouse wheel
- Space key spawns trains
- Arrow keys scroll debug log