# Accuracy Study (requirements 9.1)

**Status: not started.** This needs a LiDAR device, a laser measure and real rooms. The software side is ready: automated tests confirm the maths reproduces known synthetic geometry to within 1 mm, which says nothing about how accurate RoomPlan itself is.

## Target
Wall lengths and ceiling height within 2 to 3 cm of a laser measure under good conditions.

## Method
1. Choose at least three rooms: rectangular, L-shaped, and one with alcoves or a sloped ceiling.
2. Laser-measure every wall, the ceiling height, and each door and window. Record below.
3. Scan each room three times, tapping Export JSON each time, and save the files in `ios/RoomScanKit/Tests/RoomScanKitTests/Fixtures/real/`.
4. Read the scan's values from the review screen, or from `room.json`.
5. Repeat one room in difficult conditions: low light, a large mirror, glass, dark or shiny surfaces, heavily furnished.

## Pass or fail
A room passes if at least 90% of its wall and ceiling measurements are within 3 cm under good conditions, and repeat scans agree to within 3 cm.

## Results

| Room | Shape | Scan | Measurement | Laser (m) | Scan (m) | Error (cm) | Conditions |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
