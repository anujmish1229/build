# Room Scan and Furniture Layout: Project Requirements

Version 0.3 (draft). Date: 2026-10-31.

This version replaces v0.2, which described an earlier codebase that is not in this repository. Sections 1 to 8 are now the target for a fresh build in this repository, delivered in the versions listed in section 14. Section 9.3 and section 12 describe the earlier codebase and are kept as a list of what the rebuild must fix; `docs/STATUS.md` holds the state of this repository. Appendix A lists the changes from v0.1.

FR-S, FR-R, FR-D and FR-P keep their v0.1 numbers, with new requirements added. FR-L and FR-O were rewritten, so their numbers don't match v0.1.

## 1. Overview

### 1.1 Purpose
Let a user scan a room with a LiDAR-equipped iPhone or iPad, turn the scan into a clean numerical description of the empty room, and furnish it for a theme with real products that are guaranteed to fit. The user keeps rooms and designs in a library, browses and saves designs on a Pinterest-style Board, remixes other people's designs into their own rooms, and shares rooms and designs as files. Everything runs on the device: there is no server, account or API key.

### 1.2 Goals
- Capture accurate room dimensions (walls, ceiling height, doors, windows) with minimal user effort.
- Store the room as pure data (no pre-existing furniture) so it can be regenerated, edited, and tested.
- Choose real furniture for a theme, and place it with a deterministic solver that guarantees items fit.
- Show the result in 3D and AR, with each piece linked to its product, price and store.
- Let the user keep several rooms and designs, change designs by editing or by asking in plain words, and share them.
- Work on the device, with the only network use being a board feed the user opts into.

### 1.3 Non-goals
- Photorealistic textured scans of the room (no photogrammetry, NeRF, or Gaussian splatting).
- Scanning on phones without LiDAR. Those devices can use the rest of the app with sample and shared rooms.
- Scanning or preserving the user's existing furniture.
- Multi-storey buildings, merged multi-room homes and outdoor spaces.
- A server, user accounts, or an external LLM or image generation API.
- Buying through the app. Product links open the store's own page.
- The stores' own 3D models. Furniture is drawn in code at its real size.

### 1.4 Guiding principles
1. **Numbers first.** The room JSON is the source of truth. Models and pictures are generated from it.
2. **AI chooses, code computes.** The on-device model reads themes and requests. It never outputs coordinates; the solver places every piece.
3. **Works without AI.** Every AI feature has a built-in rules fallback, used when Apple Intelligence is unavailable or its answer can't be used.
4. **Device-independent data model.** The schema must not depend on RoomPlan types, so other scanners can feed it later.
5. **Human confirmation.** The user can verify and correct dimensions, but checking is optional unless something stops a layout.
6. **Private by default.** Nothing leaves the device unless the user sends it.

## 2. Users and Use Cases

- **Primary user:** a person furnishing or restyling a room who wants furniture suggestions that fit and can be bought.

| Id | Use case |
|---|---|
| UC1 | Scan a room, name it, and check its colours and dimensions. |
| UC2 | Correct scan errors: measure a wall, drag a corner, edit, add or delete a door or window. |
| UC3 | Enter a theme and constraints, flip through a few layouts in 3D, and keep one as a design. |
| UC4 | Change a design: swap, remove or add a piece, ask in plain words, repaint the walls, duplicate it, rename it. |
| UC5 | Share a room or a design as a file with a picture, and open files other people send. |
| UC6 | Browse the Board, filter it, and save designs to named boards. |
| UC7 | Remix a design from the Board into one of the user's rooms. |
| UC8 | Look around a room or design in 3D and AR, tap a piece and open its product page. |
| UC9 | Choose where they are, which regions to shop from, and the currency prices are shown in. |
| UC10 | Publish designs as a board feed, or subscribe to one. |
| UC11 | Rescan a room without losing corrections. |
| UC12 | Try the whole app without LiDAR, using the sample rooms. |
| UC13 | Delete their data. |

## 3. System Architecture

```
iPhone or iPad app (SwiftUI)                 RoomScanKit (Swift package, on the device)
----------------------------                 ------------------------------------------
Scan with RoomPlan        --> raw room  -->  Import, clean up, validate --> room.json
Colours sampled from camera                  Calibrate, edit, merge rescans
Review and correct        <------------>     Validation issues

Theme and constraints     ------------->     Apple Intelligence brief (iOS 26+), or rules
Layout picker             <-------------     Real catalogue pieces --> solver --> layouts
Design screen, typed edits <----------->     DesignStudio, DesignEditor (re-fitted by the solver)

Board, boards, remix      <------------->    Library, starter board, feed, ShareFiles
3D and AR viewer          <-------------     RoomScene (SceneKit), furniture forms and finishes
Settings                  ------------->     Catalogue, regions, prices

Network (optional): download a board feed from an https address the user enters
```

### 3.1 Components
| Component | Responsibility | Tech |
|---|---|---|
| Scanner | Capture room, export structure only, sample colours | Swift, RoomPlan, ARKit, Core Image |
| Review UI | Show plan and dimensions, accept corrections | SwiftUI |
| Room engine | Import, snap, trace, validate, calibrate, merge | Swift |
| Furniture catalogue | Real products with sizes, prices, links and regions | JSON, bundled or imported |
| Planner | Theme to a furniture plan | FoundationModels (iOS 26+), built-in rules |
| Placement solver | Convert placement rules into valid positions | Swift |
| Design studio and editor | Layout options, remix, swap, remove, add, move, paint | Swift |
| Library | Rooms, designs, boards, pins; on-device storage | Swift, JSON |
| Board | Starter inspiration, shared and feed designs, filters | SwiftUI |
| 3D and AR | Room shell and furniture, pictures, AR placement | SceneKit, ARKit |
| Prices and regions | Region filtering, currency conversion | Swift, bundled rates |
| Catalogue tool | Turn a retailer dataset into a catalogue file | Python (`tools/`), development only |

### 3.2 Project layout
| Path | Contents |
|---|---|
| `ios/RoomScanApp/` | SwiftUI app |
| `ios/RoomScanKit/` | Swift package with the engine, library and resources; builds and tests on a Mac |
| `ios/RoomScanUITests/` | Simulator walk-through tests |
| `ios/project.yml`, `ios/RoomScan.xcodeproj/` | XcodeGen spec and generated project |
| `contracts/` | Example scan and furnishing stream |
| `docs/` | Conventions, decisions, status |

## 4. Functional Requirements

### 4.1 Scanning (FR-S)
- **FR-S1** The app shall use RoomPlan's `RoomCaptureView` for guided capture.
- **FR-S2** The app shall detect whether the device can scan (LiDAR, iOS 16+) when a scan is started, and show a clear explanation on an unsupported device or simulator. The rest of the app remains usable.
- **FR-S3** The app shall show a pre-scan tutorial before every scan with five tips: good lighting, curtains open, walk the perimeter slowly, scan the ceiling and corners, avoid mirrors and glass. It shall state that only walls, doors and windows are kept, and that no photos or video are saved.
- **FR-S4** The app shall convert the result straight away to walls, doors, windows and openings. It shall not read or store `objects` (detected furniture).
- **FR-S5** The app shall record per-surface confidence, flag low-confidence surfaces, and show them on a sketch of the scan: orange when flagged, red when the user taps that flag.
- **FR-S6** The app shall support rescanning a room, carrying over measured walls, door swings, and edited, added or deleted openings. Corners dragged by hand are not carried over, and the app says so. The result lists what was kept.
- **FR-S7** After a scan the app shall show what was found (for example "4 walls, 1 door, 2 windows") and offer to continue or scan again.
- **FR-S8** A scan with fewer than three walls shall be refused with a plain message. It shall not replace an earlier good scan.
- **FR-S9** A failed capture shall show a plain message and offer "Scan again".
- **FR-S10** While scanning, the app shall estimate wall and floor colours from the camera about once a second, keeping only averages, never a picture (see 7.7).
- **FR-S11** The raw scan shall record the capture time and the device's model and OS version, and nothing that identifies the person.

### 4.2 Review and correction (FR-R)
Review is optional unless an error stops a layout. It opens from a new room or a room's page.
- **FR-R1** The app shall display a top-down floor plan drawn natively, with wall lengths, doors with their swing (or keep-clear square when unknown), windows, gaps and a handle on each corner, plus a 3D preview, the floor area and the ceiling height.
- **FR-R2** The user shall be able to select a wall and enter a tape-measured length, in forms such as `3.45`, `345 cm`, `11 ft 4 in` or `11' 4"`. The app shall show how the entry was read, in both unit systems. The user chooses to scale the whole plan uniformly or stretch along that wall only, sees the changes as a preview, and applies or cancels. Scale factors outside 0.5 to 2 are refused.
- **FR-R3** The user shall be able to drag corners, with snapping to neighbouring corners, and to change a door's, window's or gap's position, width, height and sill. Position is measured from the left corner as seen from inside the room.
- **FR-R3a** The user shall be able to add a door (default 0.82 × 2.03 m), window (1.0 × 1.2 m, 0.9 m sill) or doorless gap (0.9 × 2.03 m) on a wall, starting centred on it, and to delete one with confirmation.
- **FR-R4** The user shall be able to set door swing: into or out of the room, hinged left or right, or "not sure". The default is unknown, which keeps the whole area in front of the door clear.
- **FR-R5** The user shall be able to toggle metric and imperial units. Storage is always metres. The default follows the device's measurement system.
- **FR-R6** After every edit the room shall be re-validated, and each issue shown next to the wall or opening it names, on the plan and in the lists. Issues have three levels: error (stops a layout), warning (check it) and info (a default was assumed).
- **FR-R7** The user shall be able to undo edits on the review screen.
- **FR-R8** Corrections shall save to the room as they are made.

### 4.3 Room data (FR-D)
- **FR-D1** The system shall produce a canonical `room.json` conforming to the schema in 6.1.
- **FR-D2** The system shall derive: floor polygon (ordered, positive signed area), area, bounding box, perimeter, ceiling height, per-wall length.
- **FR-D3** The system shall compute wall endpoints from RoomPlan transforms (centre plus local x axis times half the width), project to the (x, z) plane, snap endpoints within 5 cm, merge collinear walls and trace a closed loop.
- **FR-D4** The system shall normalise the plan so the minimum corner is at (0, 0), with a fixed canonical rotation (`docs/CONVENTIONS.md`).
- **FR-D5** The system shall assign each opening to its nearest wall and compute `offset` along the wall and `sill` above the floor. An opening past a wall's end is slid inside: silently up to 5 cm, with a warning beyond that.
- **FR-D6** `derived` values shall be recomputed on load; they are never trusted from input.
- **FR-D7** Validation shall cover: duplicate ids; polygon corners, crossing, area and orientation; room size; walls agreeing with the outline; openings on known walls, inside their wall, and not overlapping; low confidence; unknown swing. Messages shall be plain English, in the user's units.
- **FR-D8** Size limits: a side under 0.5 m or over 50 m, or a ceiling outside 1 to 20 m, is an error; a ceiling outside 1.8 to 6 m is a warning.

### 4.4 Choosing furniture (FR-L)
- **FR-L1** The user shall enter a theme (with suggested themes offered) and optionally a must-have list, a leave-out list, and a budget. The room's colours shall be shown and editable alongside.
- **FR-L2** On iOS 26+ with Apple Intelligence available, the on-device model shall read the theme into a structured brief: room type (bedroom, living, office, dining), style words, up to 4 wanted and 4 avoided kinds of furniture, up to 3 materials, up to 3 accent colours, and a short design note. It is given the room's area and colours, and the constraints.
- **FR-L3** If the model is unavailable or fails, the built-in rules shall read the theme instead. The design shall show which of the two was used.
- **FR-L4** The model shall never output coordinates. Placement is expressed only through the rule vocabulary (6.3).
- **FR-L5** The rules shall choose the room type from the theme, else the must-haves, else the room's name, else its area (under 12 m² is a bedroom, otherwise a living room). A wanted bed always makes it a bedroom.
- **FR-L6** Each room type shall have a set of pieces with placement rules and priorities (7.5). Only catalogue products are chosen. Within a category, products are scored by style words in common, suitability to the look, harmony with the room's colours, and budget.
- **FR-L7** A must-have shall add that kind of piece or replace the plan's one, preferring a product whose name matches the other words ("car bed"). If nothing matches, a note says so. A leave-out shall remove matching pieces and anything placed relative to them.
- **FR-L8** Budget is read as the first number in the text, in the shown currency. It steers choices towards cheaper pieces and adds a note if the total goes over. It is a preference, not a hard limit.
- **FR-L9** Each piece shall carry a `priority`, so low-priority pieces are the ones dropped when space runs out.
- **FR-L10** Pieces that don't fit shall trigger one retry with the closest piece of the same kind in a similar style at least 15% smaller by footprint. The retry is kept only if more pieces fit, and each swap is reported.
- **FR-L11** The app shall offer up to three distinct layouts per design, with the main piece anchored on a different wall in each (up to five walls over 1.2 m, longest first). Only layouts placing at least as many pieces as the best minus one are offered.
- **FR-L12** The layout picker shall show one layout at a time in 3D, moved through with arrows or a swipe. Each shows a one-line summary ("Bed on the long wall, facing the window"), piece count, total price, how many didn't fit, the note, and who chose the furniture. "Use this layout" saves it.
- **FR-L13** If the theme names a look and the room's walls clash with it, the app shall ask whether the user would repaint, offering three suitable paints or "Keep my walls" (7.8). The paint applies to that design only.

### 4.5 Placement solver (FR-P)
- **FR-P1** The solver shall process items by priority, with dependent items after their targets, converting each placement rule into candidate positions and rotations.
- **FR-P2** The solver shall support rules: `against_wall`, `corner`, `centered_in_room`, `in_front_of`, `beside`, `under_window`.
- **FR-P3** Hard constraints (all must pass):
  - Footprint fully inside the floor polygon, shrunk by the safety margin.
  - No overlap with other items. Touching edges don't count.
  - No overlap with door keep-clear zones: door width by door width when it swings in or is unknown, 0.6 m deep when it swings out or there is no door.
  - No item taller than a window's sill (plus 5 cm) in that window's 0.4 m zone.
  - Each item's clearance zones kept free, except between related pairs.
  - Walkway clearance: a walker of radius `walkway_min/2 + margin` (gaps of at least 0.64 m with the defaults) must reach every door zone and a clearance zone of every placed item. It is tested on a 1 cm grid.
- **FR-P4** Soft preferences (scored): proximity to the requested wall, centring, symmetry, distance between functional pairs, and the 0.9 m preferred walkway.
- **FR-P5** On failure the solver shall try alternatives: other walls, slid positions along the wall (10 cm steps), and a rotated footprint (not for wall units such as wardrobes). If none work, it drops the item and records a reason.
- **FR-P6** The solver shall be deterministic for the same inputs and seed. Its search is limited by a work budget, not by time.
- **FR-P7** Output shall be a layout (6.5) plus a list of unplaced items with plain-English reasons.

### 4.6 Rooms (FR-M)
- **FR-M1** The user shall keep any number of named rooms, each with its floor plan, colours, corrections, last raw scan and designs. Names are made unique ("Bedroom 2").
- **FR-M2** After a scan the app shall show the plan, area and opening count, and let the user name the room, check its colours and choose "Design this room" or check the floor plan first. Design is disabled while an error stands.
- **FR-M3** The rooms list shall show a plan thumbnail, area, design count, colour swatches, the room's designs and a "New design" action.
- **FR-M4** A room's page shall show the plan, area, ceiling height, wall and opening counts, editable colours and its designs, with actions to check the floor plan, rescan, send, rename and delete. Deleting a room needs confirmation and removes its designs.
- **FR-M5** Colours shall be editable with a colour picker, with plain names ("warm off-white", "honey oak wood"), and a floor type: wood, laminate, tile, carpet or concrete.
- **FR-M6** Three sample rooms (a rectangular bedroom, a living room with an alcove and an L-shaped studio) shall be added when the library has no rooms at launch, and can be added at any time from the Rooms menu.
- **FR-M7** A room from the earlier one-room version of the app shall be migrated into the library once, as "My room".

### 4.7 Designs (FR-G)
- **FR-G1** A saved design shall hold its theme, plan, layout, note, provider, summary, products as a snapshot (so names, prices and links survive catalogue changes), its source pin if remixed, and wall paint if any.
- **FR-G2** A design's page shall show it in 3D, its summary, piece count, total price, provider and note, the paint if any, each piece as a row linked to its product page, and a "Didn't fit" list with reasons.
- **FR-G3** The user shall be able to swap a piece (for products of the same kind, best fit first), remove it (with anything placed relative to it), or add a piece from a searchable catalogue. A piece that can't fit anywhere is refused with a message. Every change is re-fitted by the solver.
- **FR-G4** The user shall be able to rename, duplicate and delete a design, and share it.

### 4.8 Changing a design in plain words (FR-E)
- **FR-E1** The user shall be able to type a change, with suggestions such as "Make it cheaper" or "Paint the walls sage".
- **FR-E2** The change vocabulary shall be: remove a piece, swap it for a product matching some words, add a kind of piece, move a piece to a wall, under a window or to the centre, and paint the walls.
- **FR-E3** With Apple Intelligence, the room and design shall be given to the model as compact JSON, and it answers with up to 8 changes. Each is checked against the design and the known kinds and colours before being applied. If the model gives nothing usable, or isn't available, rules read the text instead.
- **FR-E4** Words such as "cheaper", "smaller" and "bigger" shall restrict the choice to products that are. "Make it cheaper" with no named piece applies to every placed piece.
- **FR-E5** Each step shall be applied in order and reported in a sentence, including steps that couldn't be done and why. A move or swap that doesn't fit leaves the piece as it was. If nothing can be understood, the app shall give examples of what it can do.
- **FR-E6** The last typed change shall be undoable while the screen is open.

### 4.9 The Board (FR-B)
- **FR-B1** The home screen shall be a two-column masonry board of designs, each with a picture rendered on the device, its title, piece count and total price.
- **FR-B2** It shall show the user's own designs, then those shared with them, then the feed, then the starter inspiration. Each shows where it came from.
- **FR-B3** Filters shall cover the source (All, Yours, Shared and Feed, the last two when there are any), room type (bedroom, living, office, dining) and style (japandi, scandinavian, mid-century, modern, boho, minimalist, warm, dark).
- **FR-B4** The starter board shall have eight designs, made from the sample rooms and the catalogue in use. Designs for the built-in catalogue ship ready-made, and a test keeps them in step with the planner.
- **FR-B5** A design's page shall show its picture, source, title, price, stores, note and colours, a "Shop the look" list with product links, and actions: 3D or AR, Save, Remix, Share. A shared design can be deleted.
- **FR-B6** The user shall be able to save a design to one or more named boards, creating one on the spot. Saved designs are kept as a copy, so they survive being dropped from a feed.
- **FR-B7** The user shall be able to create, open, rename and delete boards, and remove a design from a board.
- **FR-B8** Remix shall refit a design to a chosen room (7.6): up to three layouts, its pieces kept where they fit, and a note saying how many fit. The Remix action skips the room choice if there is only one room, and is disabled if there are none.

### 4.10 Sharing and the feed (FR-H)
- **FR-H1** A room shall be sendable as a `.roomscan` file with a picture, through the share sheet. It holds the name, canonical room and colours, not the raw scan or corrections.
- **FR-H2** A design shall be sendable as a `.roomdesign` file with a picture. It holds the room, colours, plan, layout and product snapshot, so it can be viewed, shopped and remixed by someone without those products.
- **FR-H3** The app shall register both file types. Opening one (from outside, or Rooms → + → Open) shall add the room to the library or the design to the Board, and go to it.
- **FR-H4** A file that is damaged, isn't one of these, or was made by a newer app version shall be refused with a plain message.
- **FR-H5** The user shall be able to enter a feed address and refresh it from Settings or by pulling down on the Board. The last download is kept on the device.
- **FR-H6** Feed downloads shall be https only (plain http only to the device itself). An invalid or newer-format feed shall be refused.
- **FR-H7** The user shall be able to export all their designs as `board-feed.json`, to host elsewhere.

### 4.11 Catalogue (FR-C)
- **FR-C1** The app shall ship with a built-in catalogue of 27 original sample pieces with invented names and typical sizes and prices. They are not products of any retailer and have no store links.
- **FR-C2** The user shall be able to replace it by opening a catalogue file (Rooms → + → Open, or AirDrop). The imported file is kept and used from then on.
- **FR-C3** A catalogue shall be refused, keeping the current one, if it is unreadable or empty, has duplicate ids in a region, or a size that isn't three values each above 0 and below 20 m.
- **FR-C4** Product links shall only be opened if they are web links.
- **FR-C5** Catalogue order at launch: the imported file, else a catalogue built into the app, else the built-in 27.
- **FR-C6** Catalogues from other sources stay outside the repository and the build. They reach the app only when the owner opens a file on the phone (FR-C2).
- **FR-C7** Removed: the repository holds no converter or data for third-party catalogues.
- **FR-C8** A product's note (sold separately, estimated size) shall be shown to the buyer on its 3D card.
- **FR-C9** Tapping a piece or product row shall open its product page in the browser.

### 4.12 Regions and prices (FR-Z)
- **FR-Z1** The user's region shall default to the device's region, and can be changed to any region the catalogue covers.
- **FR-Z2** The user shall be able to show furniture from their region, any set of regions, or every region. A piece sold in several is shown at its cheapest, compared in US dollars.
- **FR-Z3** If the chosen regions have no furniture, the US's is used, else the first available, and Settings says so.
- **FR-Z4** Prices shall be shown in each store's currency or in any of 34 currencies, converted at rates bundled with the app (`Prices.ratesDate`, 2026-10-30). A converted price is marked `≈` with the store's own price beneath it, and Settings says conversions are approximate.
- **FR-Z5** Totals in mixed currencies shall be added up in the shown currency, else the home region's. Currencies shall use their own decimals and symbols.

### 4.13 3D, AR and pictures (FR-O)
- **FR-O1** The room shall be shown in 3D from its data: floor and walls in the room's colours, with doors and windows, at real scale in metres, Y-up, with walls outside the outline so interior dimensions are exact.
- **FR-O2** The Object view shall orbit and zoom, with walls cut away at 1.1 m like a doll's house.
- **FR-O3** On devices that support it, the AR view shall place the room on a detected floor or table at table size (8%) or real size, with see-through walls, on-screen coaching, and a "Move" action.
- **FR-O4** Tapping a piece in either view shall show a card with its name, store, price, size and note, with a "View in store" button.
- **FR-O5** Each piece shall be drawn in code at its real size, in a form that suits its kind and the design's style, in finishes taken from its product data, name or the design's look.
- **FR-O6** The look shall set what the products don't: bedding, cushions, throws, rugs, lamps and wall decor. It covers named vibes (such as japandi, steampunk, gothic, art deco, boho, industrial), materials and accent colours.
- **FR-O7** The app shall render still pictures of designs on the device for the Board and for sharing, leaving out the walls nearest the camera and art on those walls.
- **FR-O8** All outputs shall be reproducible from the room, the layout, the look and the products.

### 4.14 Settings and data (FR-T)
- **FR-T1** Settings shall hold units, region and prices, the board feed and data deletion.
- **FR-T2** "Delete everything" shall ask for confirmation, then remove all rooms, designs, boards and scans from the device.
- **FR-T3** The app shall show short messages at the bottom of the screen for saves, imports and failures. A failed save shall say so.

### 4.15 App shell (FR-U)
- **FR-U1** The Board shall be home, with one-tap access to Rooms, Boards, Scan and Settings.
- **FR-U2** The app shall use one light, editorial look regardless of the device's appearance setting.
- **FR-U3** It shall run in portrait on iPhone, and in all orientations on iPad.

## 5. Non-Functional Requirements

### 5.1 Accuracy
- Target: wall lengths and ceiling height within about 2 to 3 cm of a laser measure under good conditions (to be validated; Apple publishes no official figure).
- After user calibration (FR-R2), the calibrated wall shall match the entered value exactly, with other walls scaled consistently.
- Furniture clearance computations shall include a configurable safety margin (default 2 cm) so scan error doesn't cause real-world misfit.

### 5.2 Usability
- Scan completes in under about 3 minutes for a typical room.
- Review and correction requires at most a few taps for a common fix.
- Clear, non-technical messages throughout.

### 5.3 Performance
- Cleanup, solving and scene building for a single room: target under 10 seconds on the device, excluding the AI call. A full 60-item plan should place everything that fits in about 5 seconds.
- The AI call has a target of about 30 seconds, with progress shown.
- Long work runs off the main thread, with progress shown.

### 5.4 Privacy, security and licensing
- All processing is on the device. Nothing is sent anywhere except what the user shares. The only download is the feed the user enters.
- Room data is stored with iOS complete file protection and kept out of device backups.
- No images or video from the scan are stored; only average colours are kept.
- Sharing a room or a design, or exporting a feed, shares the room's floor plan. The share files don't include the raw scan.
- The app has no third-party analytics.
- The IKEA dataset is a third-party snapshot with no licence. Its output is for personal use and must not be published or shipped in a public app.

### 5.5 Maintainability
- Formats are versioned (6.8). Newer shared files are refused with a clear message.
- The engine consists of pure functions with unit tests and builds on a Mac without a device.
- Conventions live in `docs/CONVENTIONS.md`, with `PlanMath.swift` as their source of truth.

### 5.6 Compatibility
- iOS 16+. Scanning requires LiDAR (iPhone 12 Pro or later Pro model, iPad Pro with LiDAR). Apple Intelligence features require iOS 26+ on a supporting device.
- Development: Xcode 26 or later. Project files are generated with XcodeGen.

## 6. Data Specifications

All units are metres. Y is up, floor at y = 0. The 2D plan uses (x, z) coordinates. Rotation is in degrees about the Y axis. At rotation 0 the item's back faces −z and its front faces +z. `docs/CONVENTIONS.md` gives the full conventions.

### 6.1 `room.json`

```json
{
  "schema_version": 1,
  "units": "m",
  "source": "roomplan",
  "ceiling_height": 2.46,
  "floor_polygon": [[0,0],[4.12,0],[4.12,2.9],[2.1,2.9],[2.1,3.8],[0,3.8]],
  "walls": [
    {"id": "w0", "start": [0,0], "end": [4.12,0], "height": 2.46, "confidence": "high"},
    {"id": "w1", "start": [4.12,0], "end": [4.12,2.9], "height": 2.46, "confidence": "high"},
    {"id": "w2", "start": [4.12,2.9], "end": [2.1,2.9], "height": 2.46, "confidence": "high"},
    {"id": "w3", "start": [2.1,2.9], "end": [2.1,3.8], "height": 2.46, "confidence": "high"},
    {"id": "w4", "start": [2.1,3.8], "end": [0,3.8], "height": 2.46, "confidence": "high"},
    {"id": "w5", "start": [0,3.8], "end": [0,0], "height": 2.46, "confidence": "high"}
  ],
  "openings": [
    {"id": "d0", "type": "door", "wall_id": "w0", "offset": 0.35,
     "width": 0.9, "height": 2.03, "sill": 0.0, "swing": "inward_left"},
    {"id": "win0", "type": "window", "wall_id": "w1", "offset": 0.8,
     "width": 1.4, "height": 1.2, "sill": 0.9}
  ]
}
```

Field notes:
- `source`: `roomplan` for a scan, `manual` for the sample rooms.
- `offset`: distance along the wall from its start to the opening's near edge.
- `type`: `door`, `window`, or `opening` (doorless gap). Ids are `d`, `win` or `op` plus a number, never reusing one deleted in the same room.
- `swing`: `inward_left`, `inward_right`, `outward_left`, `outward_right`, or `unknown`. Default `unknown`, treated as a full keep-clear zone.
- `confidence`: `high`, `medium`, or `low`.
- `derived` (area, bounding box, perimeter, wall lengths) is computed on load and never written.

Validation rules: polygon closed and non-self-intersecting; walls follow the polygon in order, within 1 mm; each opening fully inside its wall; openings on one wall don't overlap, unless their height ranges differ (a fanlight over a door); `sill + height <= wall height`.

### 6.2 Raw scan
The scan as it comes from RoomPlan, with `schema_version`, `source`, `captured_at`, `device`, and lists of `walls`, `doors`, `windows` and `openings`. Each surface has `id`, `category`, 3 `dimensions`, a 16-float column-major `transform`, `confidence` and `parent_id` (iOS 17+). See `contracts/raw_room.example.json`.

### 6.3 Furniture plan

```json
{
  "theme": "calm japandi bedroom, oak and natural textures",
  "style": {"words": ["japandi"], "materials": ["oak"], "accents": []},
  "items": [
    {
      "item_id": "bed",
      "catalog_id": "structube_mumbai_bed_queen",
      "name": "MUMBAI acacia wood queen size bed",
      "category": "bed",
      "size": [1.65, 2.23, 1.0],
      "style": "",
      "placement": {"rule": "against_wall", "wall_id": "w0", "align": "center"},
      "priority": 1
    }
  ]
}
```

| Rule | Parameters |
|---|---|
| `against_wall` | `wall_id`, `align` (start, center, end) |
| `corner` | `wall_id`, `corner` (start, end) |
| `centered_in_room` | none |
| `in_front_of` | `target_item_id`, `gap` |
| `beside` | `target_item_id`, `side`, `gap` |
| `under_window` | `opening_id` |

`size` is [width, depth, height].

### 6.4 Categories
`bed`, `nightstand`, `desk`, `chair`, `wardrobe`, `dresser`, `bookshelf`, `storage`, `sofa`, `armchair`, `coffee_table`, `tv_stand`, `side_table`, `lamp`, `plant`, `dining_table`, `bench`.

### 6.5 Layout

```json
{
  "placed": [
    {"item_id": "bed", "catalog_id": "structube_mumbai_bed_queen", "category": "bed",
     "name": "MUMBAI acacia wood queen size bed", "x": 2.0, "z": 1.135, "rotation": 0,
     "footprint": [1.65, 2.23], "height": 1.0}
  ],
  "unplaced": [
    {"item_id": "sofa", "reason": "no position satisfies walkway clearance"}
  ]
}
```

`x`, `z` give the footprint centre.

### 6.6 Catalogue

```json
{
  "catalog_version": 2,
  "updated": "2026-10-29",
  "region": "CA",
  "items": [
    {
      "catalog_id": "sample_bed_queen_oak",
      "name": "Alder queen bed, oak",
      "store": "RoomScan Samples",
      "category": "bed",
      "size": [1.65, 2.15, 1.0],
      "price": 899.0,
      "currency": "CAD",
      "url": "https://example.com/alder-queen-bed",
      "styles": ["japandi", "scandinavian", "warm"],
      "clearance": {"front": 0.6, "sides": 0.5},
      "note": "Mattress sold separately.",
      "look": {"body": "oak", "form": "panel", "details": ["tall"]}
    }
  ]
}
```

Only `catalog_id`, `name`, `category` and `size` are required. `look` may also have `frame`, `upholstery` and `hardware`.

A multi-region catalogue (version 3) lists each piece once, with an `offers` map of region code to `[price, url]`, and a top-level `regions` map of region code to `currency` and `store`. It becomes one entry per region when read.

### 6.7 Library and share files
The library is stored as one JSON file, `library.json`, with these lists:

| Part | Holds |
|---|---|
| `rooms` | `id`, `name`, `createdAt`, `updatedAt`, `room`, `rawScan`, `sourceIDs`, `corrections`, `colours` |
| `designs` | `id`, `roomID`, `name`, `createdAt`, `theme`, `plan`, `layout`, `notes`, `provider`, `summary`, `products`, `remixedFrom`, `wallPaint` |
| `boards` | `id`, `name`, `pinIDs` |
| `pins` | `id`, `source` (`starter`, `feed`, `shared`, `mine`), `design` (a design package) |

Colours are `{"wall": "#RRGGBB", "floor": "#RRGGBB", "floorType": "wood", "detected": false}`.

| File | `format` | Holds |
|---|---|---|
| `.roomscan` | `roomscan.scan` | `version`, `name`, `room`, `colours`, `createdAt` |
| `.roomdesign` | `roomscan.design` | `version`, `id`, `title`, `theme`, `notes`, `roomType`, `styles`, `room`, `colours`, `plan`, `layout`, `products`, `author`, `createdAt` |
| Board feed `.json` | `roomscan.board` | `version`, `title`, `designs` (design packages) |

### 6.8 Format versions
| Format | Field | Current |
|---|---|---|
| Room, raw scan | `schema_version` | 1 |
| Catalogue | `catalog_version` | 2 (built-in), 3 (multi-region) |
| Share files, board feed | `version` | 1 |
| Exchange rates | `Prices.ratesDate` | 2026-10-30 |

## 7. Key Algorithms

### 7.1 Wall endpoints from RoomPlan
For each wall surface, centre `c` = `transform.columns.3`, direction `d` = `transform.columns.0`, half length `h = dimensions.x / 2`. Endpoints in plan: `(c.x ∓ d.x*h, c.z ∓ d.z*h)`. Length is `dimensions.x`; height is `dimensions.y`. Floor level is the lowest wall's `center.y - height/2`. A wall's height is its top above the floor, and the ceiling is the tallest wall top.

### 7.2 Polygon reconstruction
1. Snap endpoints within 5 cm.
2. Merge collinear pieces, and intersect adjacent wall lines to get true corners. Near-perpendicular walls are not forced to 90°.
3. Trace the closed loop to an ordered polygon.
4. Turn it to the canonical rotation, and move the minimum corner to the origin.
5. Validate; report issues to the user.

### 7.3 Opening assignment
For each opening, use its parent wall where known, else the nearest wall line within tolerance. `offset = dot(openingCenter - wallStart, wallDir) - width/2`. `sill = centre.y - height/2 - floorY`.

### 7.4 Placement solving
```
for item in order(items):        # priority, targets before dependants
    for candidate in generate_candidates(item.rule, room):   # walls, slides, rotations
        if satisfies_hard_constraints(candidate, room, placed):
            keep the candidate with the best soft score
    if none:
        unplaced.append(item, reason)
```
Reasons: walkway, if any position passed every other check; "does not fit inside the room" when nothing fits at all; otherwise the most common failure.

### 7.5 Pieces by room type
`main` is the anchor wall, `opposite` the wall facing it, and `side` the others, longest first. Priority is in brackets.

| Room type | Pieces |
|---|---|
| Bedroom | Bed on main (1); nightstands left and right of the bed (2); wardrobe on opposite (2); dresser on side (3); desk and chair in a side corner if asked for or over 12 m² (3); plant in a corner (4) |
| Living | Sofa on main (1); TV stand on opposite (1); coffee table in front of the sofa (2); armchair in a side corner (2); side table and lamp beside the sofa (3); bookshelf on side (3); plant in a corner (4) |
| Office | Desk on main and chair in front (1); bookshelf on opposite (2); storage on side (2); armchair in a corner (3); lamp beside the desk (3); plant in a corner (4) |
| Dining | Table centred (1); storage on main (2); bench on side (3); plant in a corner (4) |

### 7.6 Remix
For each anchor wall in the target room, take only the pieces the design actually placed. Map each rule by the wall's role (main, opposite or side) and windows to the target's windows, falling back to the same wall's role. Solve using a catalogue that merges the design's product snapshot with the user's, apply the smaller-piece retry, then pick layouts as in FR-L11.

### 7.7 Colour estimate
About once a second while tracking is normal, average a patch of the camera image: as floor when looking down, and as wall when roughly level (using the part above the middle, since furniture is usually lower). The result is the median of each set, needing at least two samples of each. Floor type is guessed: warm saturated tones are wood, near-greys are tile when light and concrete when darker, and anything else is carpet.

### 7.8 Wall paint
Sixteen groups of looks each have three paints, best first (for example cyberpunk: midnight navy, blue-black, deep purple). The first group a theme mentions is used. The walls clash if they are far from all three by a weighted colour distance. A theme that names no look never asks.

## 8. Technology Stack

| Layer | Choice | Notes |
|---|---|---|
| App | Swift, SwiftUI | iOS 16+ |
| Scanning | RoomPlan, ARKit | LiDAR required |
| Engine | Swift package (RoomScanKit) | Tools version 6.0; no third-party dependencies |
| AI | Apple FoundationModels | iOS 26+; optional |
| 3D and AR | SceneKit, ARKit | Textures drawn in code |
| Storage | JSON files | iOS file protection |
| Tests | Swift Testing, XCTest UI tests | |
| Project | XcodeGen | `ios/project.yml` |
| Catalogue tool | Python 3 | Development only |

## 9. Testing and Validation

### 9.1 Accuracy study
- Scan at least 3 real rooms of different shapes (rectangular, L-shaped, one with alcoves or sloped ceiling).
- Measure walls, ceiling height, doors, windows with a laser measure.
- Report error per measurement; set pass/fail thresholds from 5.1.
- Repeat scans of the same room to estimate repeatability.
- Test difficult conditions: low light, large mirrors, glass, dark or shiny surfaces, heavily furnished rooms.

### 9.2 Automated tests
- **Engine:** Swift Testing suites covering the scan format, room data, units, editing, storage, the solver, the planner, catalogue and prices, library, sharing, editor, 3D scene and the whole chain from scan to 3D model.
- **Recorded answers:** 168 cases recorded from the earlier Python backend: 35 imports, 54 validations, 16 calibrations, 27 merges, 22 solver layouts and 14 layout checks. 17 of the 22 layouts match exactly; the other 5 differ only at borderline walkway gaps, and must still pass every hard constraint.
- **UI:** simulator walk-throughs of the Board, saving and remixing; rooms, new designs, editing and sharing; and settings.

### 9.3 Results on 2026-10-31
| Check | Result |
|---|---|
| `swift test -c release` | 161 tests in 37 suites, all passing |
| App build, Debug, iOS Simulator (Xcode 27.1) | Succeeds |
| UI tests, iPhone 18 Pro simulator | 2 of 3 pass; see 12.4 |
| Real scan, AR, Apple Intelligence on a phone | Not run for this version |
| Accuracy study (9.1) | Not done |

### 9.4 Acceptance criteria (v1)
- A scan of a typical room produces a valid `room.json` with no manual file editing.
- Floor plan dimensions are within the accuracy target, or are corrected to exact after one-wall calibration.
- Given a theme, the system produces a layout in which 100 percent of placed items satisfy the hard constraints.
- Unplaced items are reported with reasons, and smaller pieces are tried first.
- Every feature works with Apple Intelligence off.
- Shared files open on a second device with products, prices and links intact.

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| RoomPlan idealises geometry (baseboards, radiators, alcoves, sloped ceilings) | Furniture clearance errors | Safety margin; user corrections; optionally add ARKit scene mesh later |
| Door swing not detectable | Blocked doors | Default keep-clear zone; user sets swing |
| On-device model is small or gives weak answers | Poor choices | It only reads themes; rules choose and place; every answer is checked; rules fallback |
| Apple Intelligence not available | No AI features | Rules cover every feature |
| Scan errors in poor conditions | Wrong dimensions | Tutorial; confidence flags; optional review |
| Catalogue licensing | Can't ship public catalogue | IKEA data kept for personal use; see 12 and 13 |
| Prices and exchange rates go stale | Wrong totals | Link is the source of truth; dates recorded; conversions marked approximate |
| Shared files carry a home's floor plan | Privacy | Shared only when the user chooses; no raw scan included |
| Bad imported file | Broken app | Catalogue, share and feed files are validated before use |
| LiDAR-only scanning | Smaller audience | App usable without it; device-independent schema; plan guided-AR fallback |

## 11. Roadmap

Later:
- Non-LiDAR guided-AR scanner feeding the same schema.
- ARKit mesh for fine details.
- Textured room capture.
- Direct dragging of furniture.
- Multi-room homes.

Section 12 lists work needed before a public release.

## 12. Known Gaps

### 12.1 In the engine, not reachable in the app
| Capability | State |
|---|---|
| Floor plan SVG with furniture (v0.1 FR-O1) | `RoomRenderer.svg` exists, with no screen or share action. The app shows no furnished floor plan: `FloorPlanThumbnail` can draw one, but no screen passes it a layout. |
| USDZ model file (v0.1 FR-O2) | `RoomScene.usdz` exists, with no share action or Quick Look. 3D and AR use live SceneKit scenes. |
| Catalogue download from an address | `CatalogStore.refresh` exists; no screen uses it. Only file import does. |
| Going back to the built-in catalogue | `CatalogStore.reset` exists; no screen uses it. |
| Streaming furnishing request | `POST /furnish/stream` in `OnDeviceBackend` is no longer used by the app. Design creation calls `DesignStudio` directly. |
| Custom, non-catalogue items | The plan format allows them, but the planner only chooses catalogue products. |

### 12.2 Asked for in v0.1, not built
| Requirement | State |
|---|---|
| GLB export (FR-O2) | Not built |
| Locking items in a layout (UC4) | Not built |
| Dragging furniture by hand (UC4) | Not built; pieces move by typed request only |
| Migrations for older files (5.5) | Not built; rooms and raw scans with any other `schema_version` are rejected |
| Laser accuracy study (9.1) | Not done |
| Time limit on the AI call (5.3) | Progress is shown, but no time limit is enforced |

### 12.3 Limits of the current app
- No pinch-zoom on the review plan. Walls can't be split or joined.
- Corners dragged by hand don't carry over on rescan.
- Only the last typed change can be undone. Changes from the Pieces list can't be undone.
- Selecting several regions needs a multi-region catalogue to have an effect.
- One plant's pot size isn't published (Structube FIDDLE LEAF II), so a 30 × 30 cm footprint is assumed and the app says so.

### 12.4 Defects to fix
- **Slow first Board with a large catalogue.** `testBoardPinSaveAndRemix` failed 3 of 3 runs because the Board was still showing "Arranging some inspiration…" after 30 seconds. With the IKEA catalogue bundled, the ready-made starter board is skipped and eight designs are generated at launch. Seen on a Debug simulator build; not measured on a phone.
- **Possible data loss.** `LibraryStore` falls back to an empty library if `library.json` can't be read, and the next save overwrites the file. `library.json` also has no version number.
- **Delete everything is incomplete.** It leaves the imported catalogue, the downloaded feed and the settings in place, including the feed address. Sample rooms return at the next launch.
- **Outdated wording left from the server version.** The scan result says "Continue to upload" and "after upload". The measure-a-wall sheet can say "Couldn't reach the server".
- **Unused server-shaped layer.** Review requests still go through `BackendClient` as simulated HTTP calls to `OnDeviceBackend`.

### 12.5 Needed before a public release
- A build that can't contain the IKEA catalogue. The build step in FR-C6 currently runs for every configuration, including Release.
- Permission to use the 27 built-in products, or a licensed replacement.
- An app icon. `ASSETCATALOG_COMPILER_APPICON_NAME` is empty, and there is no icon in the assets.
- A privacy manifest (`PrivacyInfo.xcprivacy`) and a privacy policy.
- The accuracy study, and hands-on device testing of scanning, review, AR and Apple Intelligence.
- ~~Source control and CI.~~ Done in 0.0: this repository and `scripts/ci.sh`.

### 12.6 Documents out of step with the code
- `docs/DECISIONS.md` still describes Gemini, the handoff zip, and `POST` routes as if they were in use.
- `docs/STATUS.md` says 133 tests (there are 161), and marks FR-O1 to O4 and O6 as done although the SVG and USDZ files can't be reached in the app.
- `docs/STATUS.md` says the IKEA catalogue isn't committed; `README.md` says it is. There is no repository yet.
- The README's simulator test command names iPhone 17 Pro, which isn't installed with Xcode 27.1 on this Mac.

## 13. Open Questions

- Is the app consumer-facing (App Store) or for personal use and demos?
- Which furniture catalogue will a public build use, and how will it be licensed and kept up to date?
- How should exchange rates and prices be refreshed, given the app otherwise avoids the network?
- Should a furnished floor plan and USDZ export return to the app (12.1), or should v1 drop them formally?
- Should board feeds warn people that they publish room floor plans?
- Should "Delete everything" also clear the catalogue, feed and settings?
- Are multi-room homes required in v1 (RoomPlan supports merging scans)?

## 14. Delivery Plan

| Version | Result | Done when |
|---|---|---|
| 0.0 Foundations | An empty app builds and CI runs | CI passes on an empty test |
| 0.1 Capture | Scan a room and export its structure as JSON | Real scans are saved as test fixtures, with no detected furniture in them |
| 0.2 Clean room data | A scan becomes a valid room.json | 3 rooms pass, and laser measurements are within 2 to 3 cm |
| 0.3 Review and correct | See the plan, fix errors, rescan without losing fixes | A measured wall matches exactly, and corrections survive a rescan |
| 0.4 Solver | A fixed furniture list is placed legally on a 2D plan | Randomised tests never break a hard constraint, and the same input gives the same layout |
| 0.5 Theme to layout | Typing a theme gives a furnished plan, or reasons why pieces don't fit | It works with Apple Intelligence off, and the model never outputs coordinates |
| 0.6 3D and AR | The room can be viewed in 3D and AR, using simple boxes | Model dimensions match room.json, and it opens in Quick Look at true scale |
| 0.7 Library and sharing | Keep multiple rooms and designs, edit them, and send them to others | Shared files open on a second phone, and files from older formats still load |
| 0.8 Board and remix | The home screen shows inspiration you can refit to your own room | The board appears immediately on first launch, and a remix fits the target room |
| 0.9 Looks and catalogue | Styled furniture, plus real products, regions and prices | Each style renders properly, and every product's data source is cleared for release |
| 1.0 Demo | A signed build on the owner's phone, for demonstration only | The signed device build succeeds, and `docs/DEMO.md` lists the demo steps |

## Appendix A: Changes from v0.1

| Area | v0.1 | v0.2 |
|---|---|---|
| Architecture | iPhone app plus Python backend | Everything on the device, in Swift |
| Furniture choice | External LLM API | Apple Intelligence (iOS 26+) reads the theme; rules choose and place, and also work alone |
| LLM feedback retry | Unplaced items go back to the LLM | Rules retry with a smaller piece |
| Outputs | SVG, GLB, USDZ, handoff package | Live 3D and AR, pictures, share files; see 12.1 |
| External handoff (FR-O5) | Required | Removed |
| Catalogue | Open question | 27 real products, file import, IKEA personal build |
| Home screen | Not specified | The Board |
| Rooms | One room at a time | Library of named rooms and designs |
| Review | Part of the main flow | Optional unless an error stops a layout |
| Non-LiDAR devices | Blocked or redirected | Scanning blocked; everything else works |

**New in v0.2:** room library (4.6), designs and editing (4.7), changes in plain words (4.8), the Board, boards and remix (4.9), sharing and feed (4.10), catalogue import and regions (4.11, 4.12), several layout options (FR-L11, FR-L12), colour sampling and wall paint (FR-S10, FR-L13), styled 3D furniture (FR-O5, FR-O6), adding and deleting openings (FR-R3a), and undo (FR-R7).

**Corrected from v0.1:**
- The 6.1 example now lists all six walls. Window `win0` moved from `w2` to `w1`, because 0.8 + 1.4 m didn't fit the 2.02 m wall. `derived` was removed from it, since it is never written.
- The 6.3 note that rotation 0 was still to be fixed is now the settled convention.
