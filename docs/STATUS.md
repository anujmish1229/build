# Status

One row per delivery version (requirements section 14). "Needs a person" lists done-when checks that software alone can't complete.

| Version | Automated checks | Needs a person |
|---|---|---|
| 0.0 | `scripts/ci.sh` passes | None |
| 0.1 | Capture contract, furniture-free export, version checks. Device build compiles the RoomPlan path | Scan real rooms on a LiDAR device, tap Export JSON, and put the files in `ios/RoomScanKit/Tests/RoomScanKitTests/Fixtures/real/`. No real scans exist yet; CI checks any that are added |
| 0.2 | Three room shapes (rectangle, L, alcove) import and validate from synthetic scans; geometry reproduced within 1 mm | The laser study in `docs/ACCURACY.md`. The 2 to 3 cm target is not yet measured |
| 0.3 | A measured wall matches to within 1e-9 m; corrections survive one and two rescans on simulated data | Rescan a real room on a device |
| 0.4 | 60 randomised rooms and plans never break a hard constraint, under the solver's checker and separate geometry checks; the same input gives the same layout | None |
