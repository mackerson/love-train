# 🚂 Love Train

A toy train simulation game built with Love2D where you can draw tracks and watch trains bounce around!

## 🎮 How to Play

- **Click and drag**: Place railway tracks (or click existing tracks to remove them)
- **Space**: Spawn a new train from the depot
- **Mouse movement**: Pan the camera around the world
- **Arrow keys (↑↓)**: Scroll through the train activity log
- **ESC**: Quit the game

## 🚂 Train Behavior

- **Red trains**: Going outbound from the depot
- **Blue trains**: Returning to the depot
- Trains automatically reverse when they hit a dead end or encounter another train
- Trains follow the exact same path back to the depot that they took going out
- Multiple trains can interact - they'll bounce off each other and return home

## 🛠️ Features

- **Smart track system**: Tracks auto-connect to nearby tracks and the depot
- **Collision detection**: Trains reverse when they encounter obstacles
- **Path tracking**: Trains remember their route for the return journey
- **Real-time logging**: Watch train activities in the scrollable log panel
- **Camera system**: Smooth mouse-following camera for exploring large track networks

## 🎯 Technical Details

- Built with Love2D (Lua game framework)
- Grid-based track placement system
- Hash map optimization for fast position lookups
- Debounced input handling for smooth track building
- Stack-based pathfinding for train return journeys

## 🚀 Running the Game

1. Install [Love2D](https://love2d.org/)
2. Clone this repository
3. Run `love .` in the project directory

## 🎨 Future Ideas

The codebase is designed to support:
- Different track types (express rails, slow rails, etc.)
- Track health/degradation system
- More complex train behaviors
- Multiple depots
- Train scheduling systems

---

*Built by Miz with AI pair programming - demonstrating clean architecture and iterative development!*
