# Neon Hopper

An original 80s-neon isometric hop-and-claim arcade game for Android, built in Godot 4.3.

- **Hop** diagonally around the pyramid (swipe diagonally, or tap a quadrant around the frog). Claim every tile to clear the level.
- **Tongue** auto-grabs flies within 2 tiles on your diagonals.
- **Cheek** holds up to 2 flies and auto-spits them at beetles/herons lined up on your diagonals.
- Fall off the edge or touch a baddie and you lose a life. Extra life every 5,000 points.

Desktop test keys: Q / E / Z / C = up-left / up-right / down-left / down-right.

## Run
Open this folder in Godot 4.3 and press Play.

## Build the APK
1. Editor > Editor Settings > Export > Android: set the Android SDK path, Java SDK path, and debug keystore.
2. Editor > Manage Export Templates: install the 4.3 templates.
3. Project > Export > Add... > Android, then Export Project (or one-click deploy to a USB-debugging phone).

## Headless self-test
`godot --headless --path . -- --autotest` plays 10 simulated minutes with a bot and prints the result.
