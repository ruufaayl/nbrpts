"use client";

import { useTransition } from "react";
import { Zap } from "lucide-react";
import { toast } from "sonner";
import { supabaseBrowser } from "@/lib/supabase/client";

export function PingButton() {
  const [isPending, startTransition] = useTransition();

  function fire() {
    startTransition(async () => {
      const { error } = await supabaseBrowser.rpc("dev_ping");
      if (error) {
        toast.error(`dev_ping failed: ${error.message}`);
      } else {
        toast.success("dev_ping fired");
      }
    });
  }

  return (
    <button
      onClick={fire}
      disabled={isPending}
      className="inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-4 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:opacity-60"
    >
      <Zap className="size-4" />
      {isPending ? "Firing..." : "Fire dev_ping()"}
    </button>
  );
}
