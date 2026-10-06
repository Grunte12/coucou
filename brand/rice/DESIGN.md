# Rice / local brand study 01

Scope: an original animated mascot/logo proof, not a new application shell or
a final commercial brand. User chose a white/gold rice grain, oval silhouette,
slightly protruding dot eyes, luminous and flexible. Preserve that direction.

Renderer: code-native SVG and independent spring channels. Shape is a tall,
slightly asymmetric tapered oval with a diagonal resting angle, not a rounded
rectangle. No mouth, limbs, ears, borrowed artwork or Coucou state tables.
Two small amber-brown (#7C5B28) eyes sit along the right contour with a thin warm
rim for contrast against a black notch. Tiny illustrations are tested at
36px and 64px in the preview. Warm fill goes #FFFEF6 → #FFF2C7 → #D7A843;
the static halo uses #E8BC58. Original vectors are in rice.svg.

Motion: spring stiffness 170/damping 25, integration in steps no larger than
1/120s with a 50ms maximum elapsed interval. State retargets keep velocity and
position. Breathing amplitude <2% and idle vertical drift <2px; a tap adds a
brief squash impulse. Seven simulated states. Reduce motion snaps to a still
pose. Hidden tabs stop rendering. This is not yet native SwiftUI integration.

Preview UI inherits the dark neutral/system-font language of the existing
workspace. Controls are labelled in Thai, keyboard focus is explicit, selected
state uses aria-pressed and the status text is live. No network APIs or sounds.

Verification: physics unit tests and interactive state/overflow checks pass;
desktop and 390px-wide screenshots reviewed. Further user feedback is required
before treating this study as the final app character or logo.
