# Companion Runtime Assets

The files in `assets/image/green_assistant/{idle,blink,move}` are the 1080x1080
Master sources. The processor never writes into those folders.

Build and validate the compact runtime variant with Python 3 and Pillow:

```text
python asset_pipeline/companion_runtime.py build
python asset_pipeline/companion_runtime.py validate
python migration/validate_companion_runtime_assets.py
```

`companion_runtime.json` defines the clips, their shared foot anchor, output
height, horizontal padding, and width alignment. For every clip the processor:

1. scans every frame's alpha;
2. computes one union bounding box;
3. applies one shared horizontal crop;
4. performs a premultiplied-alpha Lanczos downsample;
5. writes PNG frames plus JSON and Lua manifests.

The current `runtime_512` output is 256x512, but that width is derived rather
than required. A wider future action may produce a wider frame without changing
the animation player.

## Source types

`imageSequence` accepts a folder and glob pattern. `spriteSheet` accepts a
texture and an array of `sourceRect`, optional `frameSize`, and optional
`sourceOffset` descriptors. Both sources normalize to the same manifest
FrameDescriptor fields: `texture`, `sourceRect`, `sourceOffset`, frame size,
visual bounds, and foot anchor.

## Render quality presets

`GreenAssistConfig.qualityPreset` provides the isolated A/B/C/D switch:

- `A_MASTER_LINEAR`
- `B_RUNTIME_LINEAR` (current neutral default)
- `C_RUNTIME_MIPMAP`
- `D_MASTER_MIPMAP`

The preset changes only the animation asset variant and the Companion View's
NanoVG image flag. It does not change `spriteHeight`, layout, timing, movement,
dragging, or behavior.
