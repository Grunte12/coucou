# Rice mascot — original brand study

Owner-selected concept: a white/gold luminous oval rice grain, two dot eyes
slightly outside its silhouette, soft squash/stretch and interruptible motion.
This is an original vector prototype, not a copy/recolour of Mochi. It imports
no Coucou assets, sounds, character paths, animation tables or code.

Preview `preview.html` through a local HTTP server (ES module):

```sh
python3 -m http.server 8128 --bind 127.0.0.1 --directory brand/rice
```

Visit `http://127.0.0.1:8128/preview.html`. Click states, point at the grain,
tap it, pause, or turn on reduced motion. The gallery is a simulation, not
live task status. No media generation, network API, React, or third-party
animation package is needed. Run `node --test brand/rice/motion.test.mjs`.

Implementation: vector silhouette, static warm-white/gold fill and soft halo,
independent spring channels carrying velocity across state changes. Visible
animation pauses when the tab is hidden, stopped, or reduced motion is active.
The app integration should translate this own renderer/state mapping to native
SwiftUI Canvas; this preview does not replace the installed app's mascot yet.
It is not a legal clearance or trademark search for a final commercial identity.
