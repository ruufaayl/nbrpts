"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Cpu, Loader2, Play, FastForward } from "lucide-react";
import { toast } from "sonner";
import { processOneAction, processAllPendingAction } from "./actions";
import type { ProcessResult } from "@/lib/ai/types";

export function EngineControls({
  nextBrn,
  pendingCount,
}: {
  nextBrn: string | null;
  pendingCount: number;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [last, setLast] = useState<ProcessResult | null>(null);

  const runOne = () => {
    if (!nextBrn) return;
    start(async () => {
      const r = await processOneAction(nextBrn);
      setLast(r);
      if (r.ok) {
        const verdictColor =
          r.verdict === "PASS" ? "success"
          : r.verdict === "REJECT" ? "error"
          : "warning";
        toast[verdictColor as "success" | "error" | "warning"](
          `${r.brn} → ${r.verdict} (${Number(r.confidence).toFixed(2)})`,
        );
        router.refresh();
      } else {
        toast.error(r.error ?? "Process failed");
      }
    });
  };

  const runAll = () => {
    start(async () => {
      const r = await processAllPendingAction(25);
      if ("processed" in r) {
        toast.success(
          `Processed ${r.processed}: ${r.passed} pass · ${r.flagged} flag · ${r.rejected} reject (${r.duration_ms}ms)`,
        );
        router.refresh();
      } else {
        toast.error(r.error);
      }
    });
  };

  return (
    <div className="flex flex-col gap-3 rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-5">
      <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        <Cpu className="size-3.5 text-[var(--color-accent)]" /> AI Engine controls
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          disabled={pending || !nextBrn}
          onClick={runOne}
          className="inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-4 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {pending ? <Loader2 className="size-4 animate-spin" /> : <Play className="size-4" />}
          Process next ({nextBrn ?? "queue empty"})
        </button>
        <button
          type="button"
          disabled={pending || pendingCount === 0}
          onClick={runAll}
          className="inline-flex items-center gap-2 rounded-full border border-[var(--color-border)] px-4 py-2 text-sm font-medium text-[var(--color-fg)] transition hover:border-[var(--color-border-strong)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <FastForward className="size-4" />
          Process all ({pendingCount})
        </button>
      </div>
      {last ? (
        <div className="rounded-lg border border-[var(--color-border)]/60 bg-[var(--color-bg)] px-3 py-2 font-mono text-[11px] text-[var(--color-fg-muted)]">
          Last: <span className="text-[var(--color-fg)]">{last.brn}</span> →{" "}
          <span className={
            last.verdict === "PASS" ? "text-[var(--color-accent)]"
            : last.verdict === "REJECT" ? "text-[var(--color-danger)]"
            : "text-[var(--color-warn)]"
          }>{last.verdict}</span>{" "}
          confidence {Number(last.confidence ?? 0).toFixed(3)}{" "}
          {last.duration_ms ? <span className="text-[var(--color-fg-subtle)]">· {Math.round(last.duration_ms)}ms</span> : null}
        </div>
      ) : null}
    </div>
  );
}
