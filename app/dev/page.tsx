import { supabaseServer } from "@/lib/supabase/server";
import type { QueryLogRow } from "@/lib/supabase/types";
import { DevNav } from "./_components/nav";
import { QueryFeed } from "./query-feed";
import { PingButton } from "./ping-button";

export const dynamic = "force-dynamic";

async function fireDevPing() {
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
      <DevNav active="/dev" />

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
