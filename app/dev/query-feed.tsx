"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown, ChevronUp, Database } from "lucide-react";
import { supabaseBrowser } from "@/lib/supabase/client";
import type { QueryLogRow } from "@/lib/supabase/types";
import { cn, formatMs, formatTimeAgo } from "@/lib/utils";

export function QueryFeed({ initial }: { initial: QueryLogRow[] }) {
  const [rows, setRows] = useState<QueryLogRow[]>(initial);
  const [expanded, setExpanded] = useState<number | null>(null);

  useEffect(() => {
    const channel = supabaseBrowser
      .channel("query_log_feed")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "query_log" },
        (payload) => {
          setRows((current) => {
            const next = payload.new as QueryLogRow;
            if (current.some((r) => r.id === next.id)) return current;
            return [next, ...current].slice(0, 100);
          });
        }
      )
      .subscribe();

    return () => {
      supabaseBrowser.removeChannel(channel);
    };
  }, []);

  if (rows.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-[var(--color-border)] p-12 text-center">
        <Database className="mx-auto size-6 text-[var(--color-fg-subtle)]" />
        <div className="mt-3 text-sm text-[var(--color-fg-muted)]">
          No queries yet. Hit the button above to fire one.
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <AnimatePresence initial={false}>
        {rows.map((row) => {
          const isOpen = expanded === row.id;
          return (
            <motion.div
              key={row.id}
              layout
              initial={{ opacity: 0, y: -8, scale: 0.99 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, scale: 0.98 }}
              transition={{ type: "spring", stiffness: 320, damping: 28 }}
              className={cn(
                "overflow-hidden rounded-xl border bg-[var(--color-bg-card)] transition",
                isOpen
                  ? "border-[var(--color-border-strong)]"
                  : "border-[var(--color-border)] hover:border-[var(--color-border-strong)]"
              )}
            >
              <button
                onClick={() => setExpanded(isOpen ? null : row.id)}
                className="flex w-full items-center gap-4 px-4 py-3 text-left"
              >
                <span className="font-mono text-[10px] uppercase tracking-wider text-[var(--color-accent)]">
                  {row.caller}
                </span>
                <code className="flex-1 truncate font-mono text-sm text-[var(--color-fg)]">
                  {row.sql_text}
                </code>
                <span className="font-mono text-xs text-[var(--color-fg-muted)]">
                  {formatMs(row.duration_ms)}
                </span>
                <span className="hidden font-mono text-xs text-[var(--color-fg-subtle)] sm:inline">
                  {formatTimeAgo(row.ran_at)}
                </span>
                {isOpen ? (
                  <ChevronUp className="size-4 text-[var(--color-fg-muted)]" />
                ) : (
                  <ChevronDown className="size-4 text-[var(--color-fg-muted)]" />
                )}
              </button>

              <AnimatePresence initial={false}>
                {isOpen && (
                  <motion.div
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: "auto", opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.18 }}
                    className="overflow-hidden border-t border-[var(--color-border)]"
                  >
                    <div className="grid gap-4 p-4 md:grid-cols-2">
                      <Detail label="ran_at" value={row.ran_at} />
                      <Detail
                        label="rows_returned"
                        value={row.rows_returned ?? "—"}
                      />
                      <div className="md:col-span-2">
                        <div className="mb-1.5 font-mono text-[10px] uppercase tracking-wider text-[var(--color-fg-subtle)]">
                          EXPLAIN (FORMAT JSON)
                        </div>
                        <pre className="max-h-64 overflow-auto rounded-lg bg-[var(--color-bg)] p-3 font-mono text-xs leading-relaxed text-[var(--color-fg-muted)]">
                          {JSON.stringify(row.plan, null, 2)}
                        </pre>
                      </div>
                    </div>
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>
  );
}

function Detail({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div>
      <div className="font-mono text-[10px] uppercase tracking-wider text-[var(--color-fg-subtle)]">
        {label}
      </div>
      <div className="mt-1 font-mono text-sm text-[var(--color-fg)]">
        {value}
      </div>
    </div>
  );
}
