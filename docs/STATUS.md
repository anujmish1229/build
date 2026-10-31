# Status

One row per delivery version (requirements section 14). "Needs a person" lists done-when checks that software alone can't complete.

| Version | Automated checks | Needs a person |
|---|---|---|
| 0.0 | `scripts/ci.sh` passes | None |
| 0.1 | Capture contract, furniture-free export, version checks. Device build compiles the RoomPlan path | Scan real rooms on a LiDAR device, tap Export JSON, and put the files in `ios/RoomScanKit/Tests/RoomScanKitTests/Fixtures/real/`. No real scans exist yet; CI checks any that are added |
