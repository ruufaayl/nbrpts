import type { RecordStatus } from "@/lib/domain/types";

const styles: Record<
  RecordStatus,
  { label: string; bg: string; fg: string }
> = {
  PENDING:  { label: "PENDING",  bg: "var(--color-bg-elev)",      fg: "var(--color-fg)" },
  FLAGGED:  { label: "FLAGGED",  bg: "color-mix(in oklch, var(--color-warn) 25%, transparent)", fg: "var(--color-warn)" },
  VERIFIED: { label: "VERIFIED", bg: "color-mix(in oklch, var(--color-accent) 25%, transparent)", fg: "var(--color-accent)" },
  REJECTED: { label: "REJECTED", bg: "color-mix(in oklch, var(--color-danger) 25%, transparent)", fg: "var(--color-danger)" },
  AMENDED:  { label: "AMENDED",  bg: "var(--color-bg-elev)",      fg: "var(--color-fg-muted)" },
};

export function StatusBadge({ status }: { status: RecordStatus }) {
  const s = styles[status] ?? styles.PENDING;
  return (
    <span
      className="inline-flex items-center rounded-full px-2 py-0.5 font-mono text-[10px] font-medium uppercase tracking-widest"
      style={{ background: s.bg, color: s.fg }}
    >
      {s.label}
    </span>
  );
}
