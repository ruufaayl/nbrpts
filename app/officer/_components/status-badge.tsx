import type { RecordStatus } from "@/lib/domain/types";

const STYLES: Record<RecordStatus, { fg: string; bg: string; ring: string }> = {
  PENDING:  { fg: "var(--color-fg)",     bg: "color-mix(in oklch, var(--color-fg) 8%, transparent)", ring: "var(--color-border)" },
  FLAGGED:  { fg: "var(--color-warn)",   bg: "color-mix(in oklch, var(--color-warn) 14%, transparent)", ring: "color-mix(in oklch, var(--color-warn) 30%, transparent)" },
  VERIFIED: { fg: "var(--color-accent)", bg: "color-mix(in oklch, var(--color-accent) 14%, transparent)", ring: "color-mix(in oklch, var(--color-accent) 30%, transparent)" },
  REJECTED: { fg: "var(--color-danger)", bg: "color-mix(in oklch, var(--color-danger) 14%, transparent)", ring: "color-mix(in oklch, var(--color-danger) 30%, transparent)" },
  AMENDED:  { fg: "var(--color-fg-muted)", bg: "color-mix(in oklch, var(--color-fg) 8%, transparent)", ring: "var(--color-border)" },
};

export function StatusBadge({ status }: { status: RecordStatus }) {
  const s = STYLES[status] ?? STYLES.PENDING;
  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[10px] uppercase tracking-widest ring-1"
      style={{ color: s.fg, backgroundColor: s.bg, boxShadow: `inset 0 0 0 1px ${s.ring}` }}
    >
      {status}
    </span>
  );
}
