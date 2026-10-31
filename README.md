# Poltar

Poltar is an iOS app that scans a real room and furnishes it with real products that are guaranteed to fit. Everything runs on the device, with no server, account or API key.

Created by Anirud, Anuj, Suad and Tamir.

## What it does

- **Scan a room:** use a LiDAR iPhone or iPad to get a clean floor plan of the empty room, then correct it with tape-measured wall lengths and editable doors and windows. Sample rooms let you try the app without LiDAR.
- **Design by theme:** describe a look, such as "calm japandi bedroom", add a budget or must-have pieces, and choose from up to three layouts.
- **View in 3D and AR:** walk around the room, and tap a piece to see its size, price and store link.
- **Change it in plain words:** say "make it cheaper" or "remove the plant", or swap and add pieces by hand. Apple Intelligence interprets requests where it's available, and built-in rules work without it.
- **Browse the Board:** filter ready-made designs by room and style, including Halloween and Christmas, save them to your own boards, and remix any of them into your own room.
- **Share:** send rooms and designs as files, export a floor plan as SVG, or publish your designs as a board feed.

## Requirements

- Xcode 16 or later, on macOS 14 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- iOS 16 or later to run the app, and a LiDAR device to scan

## Getting started

The Xcode project is generated and isn't checked in:

```sh
cd ios
xcodegen generate
open Poltar.xcodeproj
```

Run the `Poltar` scheme on a simulator or device. Scanning needs a real LiDAR device, but everything else works in the simulator.

To build and install a signed copy on a connected iPhone:

```sh
scripts/build_device.sh --install
```

## Tests

```sh
scripts/ci.sh        # engine tests and app builds
scripts/ci.sh --ui   # also runs the simulator walk-through tests
```

The engine tests also run on their own on a Mac:

```sh
cd ios/PoltarKit
swift test
```

## Furniture catalogue

The app includes a small catalogue of sample furniture. To use real IKEA products instead, download the [IKEA catalogue CSV](https://www.kaggle.com/datasets/ranjithpanicker/ikea-global-product-catalog-and-price-2026) and run:

```sh
scripts/build_ikea_catalog.sh path/to/IKEA_product_catalog.csv [region]
```

This writes to `catalog-local/`, which is gitignored and built into the app when present. The region defaults to `CA`.

## Project layout

| Path | Contents |
|---|---|
| `ios/PoltarApp` | The SwiftUI app: Board, rooms, designs, 3D and AR viewer, settings |
| `ios/PoltarKit` | The on-device engine: room geometry, furniture planner and layout solver, catalogue, library, share files |
| `ios/PoltarUITests` | Simulator walk-through tests |
| `ios/project.yml` | XcodeGen project definition |
| `contracts` | Example of the raw scan format |
| `scripts`, `tools` | CI, device build and catalogue scripts |

## Known issues

- Tapping **Quick Look** in the 3D viewer crashes the app. This was seen in the simulator, inside SceneKit's USDZ export called from `RoomScene.writeUSDZ`.
