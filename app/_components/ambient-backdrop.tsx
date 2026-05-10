// Animated mesh-gradient backdrop. Pure CSS — runs everywhere, accepts
// reduced-motion preference, and sits behind a subtle grid for the
// "governmental command-center" feel.
export function AmbientBackdrop() {
  return (
    <div aria-hidden className="mesh-backdrop">
      <div className="bg-grid absolute inset-0 opacity-60" />
      <div
        className="mesh-blob mesh-blob-1"
        style={{
          top: "-15%",
          left: "-10%",
          width: "55vw",
          height: "55vw",
          background:
            "radial-gradient(circle at center, oklch(0.78 0.16 158 / 0.45), transparent 70%)",
        }}
      />
      <div
        className="mesh-blob mesh-blob-2"
        style={{
          top: "30%",
          right: "-15%",
          width: "50vw",
          height: "50vw",
          background:
            "radial-gradient(circle at center, oklch(0.65 0.14 240 / 0.35), transparent 70%)",
        }}
      />
      <div
        className="mesh-blob mesh-blob-3"
        style={{
          bottom: "-20%",
          left: "20%",
          width: "60vw",
          height: "60vw",
          background:
            "radial-gradient(circle at center, oklch(0.7 0.12 280 / 0.25), transparent 70%)",
        }}
      />
      {/* Vignette for depth */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse at center, transparent 30%, oklch(0.13 0.005 240 / 0.85) 90%)",
        }}
      />
    </div>
  );
}
