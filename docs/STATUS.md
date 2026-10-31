# Status

One row per delivery version (requirements section 14). "Needs a person" lists done-when checks that software alone can't complete.

| Version | Automated checks | Needs a person |
|---|---|---|
| 0.0 | `scripts/ci.sh` passes | None |
| 0.1 | Capture contract, furniture-free export, version checks. Device build compiles the RoomPlan path | Scan real rooms on a LiDAR device, tap Export JSON, and put the files in `ios/RoomScanKit/Tests/RoomScanKitTests/Fixtures/real/`. No real scans exist yet; CI checks any that are added |
| 0.2 | Three room shapes (rectangle, L, alcove) import and validate from synthetic scans; geometry reproduced within 1 mm | The laser study in `docs/ACCURACY.md`. The 2 to 3 cm target is not yet measured |
| 0.3 | A measured wall matches to within 1e-9 m; corrections survive one and two rescans on simulated data | Rescan a real room on a device |
| 0.4 | 60 randomised rooms and plans never break a hard constraint, under the solver's checker and separate geometry checks; the same input gives the same layout | None |
| 0.5 | Every room type designs legally with Apple Intelligence off; a brief has no field for a position, and junk from a stubbed model is dropped | Try a theme with Apple Intelligence on, on a supported phone |
| 0.6 | Scene boxes match room.json; a USDZ file reloaded from disk measures the room's true size within 1 mm | Open Quick Look and AR on a phone and check the scale by eye |
| 0.7 | Library, share files, typed changes and paint tested; older-format library and share files load; a damaged or newer library is kept, not overwritten | Send a file to a second phone and open it |
| 0.8 | The ready-made Board loads with no solving, and a test keeps it in step with the planner; remixes fit their target room; simulator walk-throughs | Try the flow on the phone |
| 0.9 | Every sample product in 14 looks stays inside its stated size; five looks render non-blank pictures; prices, regions and catalogue import tested | The built-in pieces are invented samples, not real products. A real catalogue can be opened as a file on the phone |
