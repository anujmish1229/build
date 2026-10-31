# Conventions

`ios/RoomScanKit/Sources/RoomScanKit/PlanMath.swift` is the source of truth; this page explains it.

## Units and axes
- All stored values are metres. Units are a display concern only (`Units.swift`).
- Y is up and the floor is y = 0. The 2D plan uses (x, z).
- A top-down drawing maps x to the screen's x and z to the screen's y.

## Floor polygon
- Ordered with positive signed area: `½ Σ (xᵢ·zᵢ₊₁ − xᵢ₊₁·zᵢ) > 0`.
- Walking a wall from `start` to `end`, the room is on the left in (x, z); the inward normal of direction `(dx, dz)` is `(−dz, dx)`.
- `walls[i]` runs from `floor_polygon[i]` to `floor_polygon[i+1]`.

## Canonical pose (FR-D4)
1. The longest wall (first in loop order on a tie within 1 mm) is rotated to run along +x with the room on its +z side.
2. The plan is translated so the bounding box minimum is (0, 0).
3. The loop starts at the corner with the smallest z, then the smallest x.

## Openings
- `offset` is the distance along the wall from `start` to the opening's near edge. Seen from inside the room, `start` is the left corner.
- `left`/`right` in a door swing are as seen from inside the room, facing the door.

## Furniture
- `size` is `[width, depth, height]`. `x`, `z` give the footprint centre.
- Rotation is degrees about +Y. At rotation 0 the back faces −z and the front faces +z. Front direction is `(sin θ, cos θ)`, local width axis is `(cos θ, −sin θ)`.
- `beside` with `side: left` means the target's local −x side.

## Clearance (FR-P3)
- A front clearance zone must lie inside the room and be free of unrelated items. Side zones must be free of unrelated items; a wall may bound them.
- Related pairs are an item and its `in_front_of` or `beside` target, and siblings sharing that target.
- The walker "reaches" a zone when its disc overlaps the zone.

## Code
- The engine is pure functions on value types and never imports UIKit. Platform frameworks are behind `#if canImport`.
- No third-party dependencies. New formats get a version field (requirements 6.8).
- Run `scripts/ci.sh` before every commit.
