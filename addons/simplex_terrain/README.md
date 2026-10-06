# SimpleXTerrain Addon

This directory contains the core files for the **SimpleXTerrain** procedural generation addon for Godot 4 .NET.

## Quick Installation

1. Drag-and-drop this entire `simplex_terrain` folder into your project's `res://addons/` directory.
2. Ensure you have the C# version of Godot 4.6+ and .NET SDK 8.0+ configured.
3. Ensure **Terrain3D** is installed and enabled in your project.
4. Build the project solution (`dotnet build` or click "Build" in the top-right of the Godot editor).
5. Enable `SimpleXTerrain` under **Project Settings -> Plugins**.

## Contents

- `src/` - Core C# implementation of the node graph, node evaluation, and chunk streamer.
- `shaders/` - GPU compute shaders used for terrain calculations.
- `demo/` - Complete self-contained demo scene (`infinite_demo.tscn`), FlyCamera script, textures, and Whittaker 10-biome presets.
- `plugin.cfg` - Plugin metadata.

For detailed setup instructions, node guides, and API reference, please refer to the [SimpleXTerrain Documentation](https://github.com/prajwal-mx/simplex-terrain-docs).
