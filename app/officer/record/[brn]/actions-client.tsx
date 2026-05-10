"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, X, AlertTriangle, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { verifyRecordAction, rejectRecordAction, flagRecordAction, type ActionResult } from "../../actions";

type Mode = null | "verify" | "reject" | "flag";

export function RecordActions({ brn, status }: { brn: string; status: string }) {
  const [mode, setMode] = useState<Mode>(null);
  const [remarks, setRemarks] = useState("");
  const [pending, start] = useTransition();
  const router = useRouter();

  const canVerify = status === "PENDING" || status === "FLAGGED";
  const canReject = status === "PENDING" || status === "FLAGGED";
  const canFlag   = status === "PENDING";

  const dispatch = (fn: () => Promise<ActionResult>, success: string) => {
    start(async () => {
      const r = await fn();
      if (r.ok) {
        toast.success(success);
        setMode(null);
        setRemarks("");
        router.refresh();
      } else {
        toast.error(r.error ?? "Failed");
      }
    });
  };

  if (mode === null) {
    return (
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          disabled={!canVerify}
          onClick={() => setMode("verify")}
          className="inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-4 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
        >
          <Check className="size-4" />
          Verify
        </button>
        <button
          type="button"
          disabled={!canReject}
          onClick={() => setMode("reject")}
          className="inline-flex items-center gap-2 rounded-full border border-[var(--color-danger)]/40 px-4 py-2 text-sm font-medium text-[var(--color-danger)] transition hover:bg-[var(--color-danger)]/10 disabled:cursor-not-allowed disabled:opacity-40"
        >
          <X className="size-4" />
          Reject
        </button>
        <button
          type="button"
          disabled={!canFlag}
          onClick={() => setMode("flag")}
          className="inline-flex items-center gap-2 rounded-full border border-[var(--color-warn)]/40 px-4 py-2 text-sm font-medium text-[var(--color-warn)] transition hover:bg-[var(--color-warn)]/10 disabled:cursor-not-allowed disabled:opacity-40"
        >
          <AlertTriangle className="size-4" />
          Flag
        </button>
      </div>
    );
  }

  const titles: Record<NonNullable<Mode>, string> = {
    verify: "Verify this record?",
    reject: "Reject this record",
    flag:   "Flag for further review",
  };
  const placeholders: Record<NonNullable<Mode>, string> = {
    verify: "Optional notes (visible in audit log)",
    reject: "Required reason — the hospital will see this and can resubmit.",
    flag:   "Why is this being flagged?",
  };
  const required = mode === "reject";

  return (
    <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-elev)] p-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-[var(--color-fg)]">{titles[mode]}</h3>
        <button
          type="button"
          onClick={() => { setMode(null); setRemarks(""); }}
          className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
        >
          Cancel
        </button>
      </div>
      <textarea
        value={remarks}
        onChange={(e) => setRemarks(e.target.value)}
        placeholder={placeholders[mode]}
        required={required}
        rows={3}
        className="mt-3 w-full resize-none rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm focus:border-[var(--color-accent)] focus:outline-none"
      />
      <div className="mt-3 flex items-center justify-end gap-2">
        <button
          type="button"
          disabled={pending || (required && !remarks.trim())}
          onClick={() => {
            if (mode === "verify")
              dispatch(() => verifyRecordAction(brn, remarks), `Verified ${brn}`);
            else if (mode === "reject")
              dispatch(() => rejectRecordAction(brn, remarks), `Rejected ${brn}`);
            else
              dispatch(() => flagRecordAction(brn, remarks), `Flagged ${brn}`);
          }}
          className={
            "inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-40 " +
            (mode === "verify"
              ? "bg-[var(--color-accent)] text-[var(--color-accent-fg)] hover:opacity-90"
              : mode === "reject"
                ? "bg-[var(--color-danger)] text-white hover:opacity-90"
                : "bg-[var(--color-warn)] text-black hover:opacity-90")
          }
        >
          {pending && <Loader2 className="size-4 animate-spin" />}
          Confirm {mode}
        </button>
      </div>
    </div>
  );
}
