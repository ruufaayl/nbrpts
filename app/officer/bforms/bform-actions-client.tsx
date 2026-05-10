"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Check, RotateCw, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { authorizeBformAction, reissueBformAction } from "../actions";

export function AuthorizeButton({ bformId, bformNumber }: { bformId: string; bformNumber: string }) {
  const [pending, start] = useTransition();
  const router = useRouter();
  return (
    <button
      type="button"
      disabled={pending}
      onClick={() =>
        start(async () => {
          const r = await authorizeBformAction(bformId);
          if (r.ok) {
            toast.success(`${bformNumber} authorized`);
            router.refresh();
          } else {
            toast.error(r.error ?? "Failed");
          }
        })
      }
      className="inline-flex items-center gap-1.5 rounded-full bg-[var(--color-accent)] px-3 py-1 text-xs font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:opacity-40"
    >
      {pending ? <Loader2 className="size-3 animate-spin" /> : <Check className="size-3" />}
      Authorize
    </button>
  );
}

export function ReissueButton({ childId, childName }: { childId: string; childName: string }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [pending, start] = useTransition();
  const router = useRouter();

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1.5 rounded-full border border-[var(--color-border)] px-3 py-1 text-xs text-[var(--color-fg-muted)] transition hover:border-[var(--color-border-strong)] hover:text-[var(--color-fg)]"
      >
        <RotateCw className="size-3" /> Reissue
      </button>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <input
        autoFocus
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder={`Reason for ${childName}`}
        className="rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-2 py-1 text-xs focus:border-[var(--color-accent)] focus:outline-none"
      />
      <button
        type="button"
        disabled={pending || !reason.trim()}
        onClick={() =>
          start(async () => {
            const r = await reissueBformAction(childId, reason);
            if (r.ok) {
              toast.success("B-Form reissued");
              setOpen(false);
              setReason("");
              router.refresh();
            } else {
              toast.error(r.error ?? "Failed");
            }
          })
        }
        className="inline-flex items-center gap-1.5 rounded-full bg-[var(--color-accent)] px-3 py-1 text-xs font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:opacity-40"
      >
        {pending && <Loader2 className="size-3 animate-spin" />}
        Reissue
      </button>
      <button
        type="button"
        onClick={() => { setOpen(false); setReason(""); }}
        className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
      >
        Cancel
      </button>
    </div>
  );
}
