# Demo Checklist

## Install

1. Plug in the iPhone and unlock it. Tap **Trust** if it asks.
2. Turn on **Settings > Privacy & Security > Developer Mode** if it's off. The phone restarts.
3. Run `scripts/build_device.sh --install`.
4. If the app won't open, go to **Settings > General > VPN & Device Management** and trust your developer certificate.

## Demo

The first launch is a good place to start, so delete the app first if you want a clean run.

**No LiDAR needed**

- [ ] **Board:** It shows straight away, and pictures fill in. Try the Bedroom and Japandi filters.
- [ ] **Save:** Open a design, tap **Save to a board**, and create a board.
- [ ] **Remix:** On the same design, tap **Remix into my room** and pick a sample room. Swipe through the layouts and tap **Use this layout**.
- [ ] **New design:** Tap the Rooms icon, then **New design** on a sample room. Type `calm japandi bedroom` and tap **Show me layouts**.
- [ ] **Typed change:** On the design, type `remove the plant and add a bench`, then tap **Undo that change**. Tap **Paint the walls sage**.
- [ ] **Measure a wall:** On a room, tap **Check the floor plan**, tap a wall, enter `345 cm`, and apply. Drag a corner, then undo.
- [ ] **Settings:** Show prices in another currency, and see the ≈ on a design.

**On a LiDAR phone**

- [ ] **Scan:** Tap the camera icon, read the tips, and scan a room. The result lists what was found.
- [ ] **Design your room:** Name it, tap **Design this room**, and keep a layout.
- [ ] **AR:** Tap **View in 3D and AR**, switch to **AR**, and tap the floor to place the room. Tap a piece to see its card.
- [ ] **Quick Look:** In the same viewer, tap **Quick Look**.
- [ ] **Rescan:** Measure a wall, then rescan from the room's page. The result says what was kept.

## What to say if asked

- The built-in furniture is invented sample data, so prices are made up and pieces have no store links. Opening a catalogue file on the phone replaces it.
- Everything runs on the phone. The only download is a feed you add yourself.

## Not yet tried on a real phone

Automated tests and the simulator cover the rest. These have never been run on a device, so try them before an audience sees them:

- Scanning, colour sampling, rescanning, AR and Quick Look
- Apple Intelligence: the design says which of it or the built-in rules chose the furniture
- Opening a shared file on a second phone
- Scan accuracy against a laser measure (`docs/ACCURACY.md`)
