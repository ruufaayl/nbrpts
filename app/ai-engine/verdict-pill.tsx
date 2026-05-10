import type { AiVerdict } from "@/lib/ai/types";

const TONES: Record<AiVerdict, { fg: string; bg: string }> = {
  PASS:   { fg: "var(--color-accent)", bg: "color-mix(in oklch, var(--color-accent) 14%, transparent)" },
  FLAG:   { fg: "var(--color-warn)",   bg: "color-mix(in oklch, var(--color-warn) 14%, transparent)" },
  REJECT: { fg: "var(--color-danger)", bg: "color-mix(in oklch, var(--color-danger) 14%, transparent)" },
};

export function VerdictPill({ verdict }: { verdict: AiVerdict }) {
  const t = TONES[verdict] ?? TONES.FLAG;
  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[10px] uppercase tracking-widest"
      style={{ color: t.fg, backgroundColor: t.bg }}
    >
      {verdict}
    </span>
  );
}
