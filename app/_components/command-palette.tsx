"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import {
  Search, Hospital, ShieldCheck, Brain, Database,
  Network, Zap, FileText, Inbox, Cpu, Users, BarChart3,
  ArrowRight, Command, FileCheck2,
} from "lucide-react";

type Cmd = {
  href: string;
  label: string;
  group: "Portals" | "Hospital" | "Officer" | "Observatory" | "Account";
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>;
  hint?: string;
};

const COMMANDS: Cmd[] = [
  // Portals
  { href: "/",            label: "Landing",                group: "Portals", icon: ArrowRight,  hint: "Cinematic overview" },
  { href: "/hospital",    label: "Hospital portal",        group: "Portals", icon: Hospital,    hint: "aku@nbrpts.demo" },
  { href: "/ai-engine",   label: "AI Engine",              group: "Portals", icon: Brain,       hint: "Live verification" },
  { href: "/officer",     label: "Officer dashboard",      group: "Portals", icon: ShieldCheck, hint: "aisha@nbrpts.demo" },

  // Hospital
  { href: "/hospital/submit",      label: "Submit a birth record",   group: "Hospital", icon: FileText },
  { href: "/hospital/submissions", label: "All submissions",         group: "Hospital", icon: Inbox },
  { href: "/hospital/device",      label: "Device simulator",        group: "Hospital", icon: Cpu },

  // Officer
  { href: "/officer/queue",   label: "Review queue",         group: "Officer", icon: Inbox },
  { href: "/officer/bforms",  label: "B-Forms workload",     group: "Officer", icon: FileCheck2 },
  { href: "/officer/search",  label: "Record search",        group: "Officer", icon: Search },
  { href: "/officer/stats",   label: "Population stats",     group: "Officer", icon: BarChart3 },

  // Observatory
  { href: "/dev",          label: "Query feed",          group: "Observatory", icon: Database },
  { href: "/dev/schema",   label: "Live ER diagram",     group: "Observatory", icon: Network },
  { href: "/dev/triggers", label: "Trigger lab",         group: "Observatory", icon: Zap },

  // Account
  { href: "/login",        label: "Sign in",             group: "Account",     icon: Users },
];

export function CommandPalette() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [highlight, setHighlight] = useState(0);

  // Cmd/Ctrl-K toggle
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((v) => !v);
      }
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return COMMANDS;
    return COMMANDS.filter(
      (c) =>
        c.label.toLowerCase().includes(q) ||
        c.group.toLowerCase().includes(q) ||
        c.hint?.toLowerCase().includes(q),
    );
  }, [query]);

  useEffect(() => {
    setHighlight(0);
  }, [query, open]);

  const grouped = useMemo(() => {
    const groups: Record<string, Cmd[]> = {};
    filtered.forEach((c) => {
      groups[c.group] = groups[c.group] ?? [];
      groups[c.group].push(c);
    });
    return groups;
  }, [filtered]);

  const onKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setHighlight((h) => Math.min(h + 1, filtered.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setHighlight((h) => Math.max(h - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      const item = filtered[highlight];
      if (item) {
        router.push(item.href);
        setOpen(false);
        setQuery("");
      }
    }
  };

  let cursor = -1;

  return (
    <AnimatePresence>
      {open ? (
        <motion.div
          key="cmdk"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
          className="fixed inset-0 z-50 flex items-start justify-center px-4 pt-[10vh]"
          onClick={() => setOpen(false)}
          style={{ background: "oklch(0 0 0 / 0.55)", backdropFilter: "blur(8px)" }}
        >
          <motion.div
            initial={{ y: -16, opacity: 0, scale: 0.98 }}
            animate={{ y: 0, opacity: 1, scale: 1 }}
            exit={{ y: -8, opacity: 0, scale: 0.98 }}
            transition={{ duration: 0.18, ease: [0.2, 0, 0, 1] }}
            onClick={(e) => e.stopPropagation()}
            className="glass glass-highlight w-full max-w-xl overflow-hidden rounded-2xl"
          >
            <div className="flex items-center gap-3 border-b border-[var(--glass-border)] px-4 py-3">
              <Search className="size-4 text-[var(--color-fg-muted)]" />
              <input
                autoFocus
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={onKey}
                placeholder="Jump to anything…"
                className="flex-1 bg-transparent text-sm text-[var(--color-fg)] outline-none placeholder:text-[var(--color-fg-subtle)]"
              />
              <kbd className="hidden rounded border border-[var(--glass-border)] bg-[var(--glass-bg)] px-1.5 py-0.5 font-mono text-[10px] text-[var(--color-fg-subtle)] sm:inline-block">
                ESC
              </kbd>
            </div>

            <div className="max-h-[60vh] overflow-y-auto px-2 py-2">
              {filtered.length === 0 ? (
                <div className="px-3 py-12 text-center text-sm text-[var(--color-fg-subtle)]">
                  No matches.
                </div>
              ) : (
                Object.entries(grouped).map(([group, items]) => (
                  <div key={group} className="mb-2 last:mb-0">
                    <div className="px-3 py-1.5 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                      {group}
                    </div>
                    <ul>
                      {items.map((item) => {
                        cursor++;
                        const isActive = cursor === highlight;
                        const Icon = item.icon;
                        return (
                          <li key={item.href}>
                            <button
                              type="button"
                              onMouseEnter={() => setHighlight(cursor)}
                              onClick={() => {
                                router.push(item.href);
                                setOpen(false);
                                setQuery("");
                              }}
                              className={
                                "group flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-sm transition " +
                                (isActive
                                  ? "bg-[var(--color-accent)]/15 text-[var(--color-fg)]"
                                  : "text-[var(--color-fg-muted)] hover:bg-[var(--glass-bg)]")
                              }
                            >
                              <Icon
                                className={
                                  "size-4 " +
                                  (isActive ? "text-[var(--color-accent)]" : "text-[var(--color-fg-subtle)]")
                                }
                              />
                              <span className="flex-1">{item.label}</span>
                              {item.hint ? (
                                <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                                  {item.hint}
                                </span>
                              ) : null}
                              {isActive ? (
                                <ArrowRight className="size-3.5 text-[var(--color-accent)]" />
                              ) : null}
                            </button>
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                ))
              )}
            </div>

            <div className="flex items-center justify-between border-t border-[var(--glass-border)] px-4 py-2 font-mono text-[10px] text-[var(--color-fg-subtle)]">
              <span className="flex items-center gap-1">
                <Command className="size-3" /> K toggles · ↑↓ navigate · ↵ open
              </span>
              <span>NBRPTS</span>
            </div>
          </motion.div>
        </motion.div>
      ) : null}
    </AnimatePresence>
  );
}
