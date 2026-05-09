import Link from "next/link";
import { ArrowLeft, Activity } from "lucide-react";
import { supabaseServer } from "@/lib/supabase/server";
import type { QueryLogRow } from "@/lib/supabase/types";
import { QueryFeed } from "./query-feed";
import { PingButton } from "./ping-button";

export const dynamic = "force-dynamic";

async function fireDevPing() {
  // Server-side: hit the RPC once on every page load so the feed is never empty.
  await supabaseServer.rpc("dev_ping");
}

async function loadInitialFeed(): Promise<QueryLogRow[]> {
  const { data, error } = await supabaseServer
    .from("query_log")
    .select("*")
    .order("ran_at", { ascending: false })
    .limit(50);
  if (error) {
    console.error("[dev] failed to load query_log:", error.message);
    return [];
  }
  return data as QueryLogRow[];
}

export default async function DevObservatoryPage() {
  await fireDevPing();
  const initial = await loadInitialFeed();

  return (
    <main className="min-h-screen">
      <div className="border-b border-[var(--color-border)]">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-sm text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
          >
            <ArrowLeft className="size-4" />
            Back
          </Link>
          <div className="flex items-center gap-2 font-mono text-xs uppercase tracking-widest text-[var(--color-fg-muted)]">
            <Activity className="size-3.5 text-[var(--color-accent)]" />
            Database Observatory
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-6xl px-6 py-12">
        <div className="flex flex-wrap items-end justify-between gap-6">
          <div>
            <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
              Live query feed
            </h1>
            <p className="mt-2 max-w-xl text-sm leading-relaxed text-[var(--color-fg-muted)]">
              Every tracked SQL call the app makes is appended to{" "}
              <code className="font-mono text-[var(--color-fg)]">
                public.query_log
              </code>{" "}
              and streamed to this page via Supabase Realtime. Click the button
              to fire a fresh{" "}
              <code className="font-mono text-[var(--color-fg)]">dev_ping()</code>{" "}
              RPC and watch it land in real time.
            </p>
          </div>
          <PingButton />
        </div>

        <div className="mt-10">
          <QueryFeed initial={initial} />
        </div>
      </div>
    </main>
  );
}
