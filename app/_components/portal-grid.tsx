"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import {
  Hospital, Brain, ShieldCheck, Database,
  ArrowUpRight,
} from "lucide-react";

type Card = {
  href: string;
  eyebrow: string;
  title: string;
  body: string;
  icon: React.ComponentType<{ className?: string; style?: React.CSSProperties }>;
  hue: string; // gradient hue for glow
  bullets: string[];
};

const CARDS: Card[] = [
  {
    href: "/hospital",
    eyebrow: "01 — Front line",
    title: "Hospital portal",
    body: "Offline-first birth-record entry. Auto-syncs when connectivity returns. Tamper-proof local storage.",
    icon: Hospital,
    hue: "oklch(0.78 0.16 158)",
    bullets: ["4-step submit form", "IndexedDB device", "RLS-scoped to facility"],
  },
  {
    href: "/ai-engine",
    eyebrow: "02 — Verification",
    title: "AI Engine",
    body: "Eight signals across age, weight, CNIC, duplicates, outcome. Auto-approves on high confidence; queues anomalies.",
    icon: Brain,
    hue: "oklch(0.7 0.16 220)",
    bullets: ["Pure-SQL rules", "ai_review_log", "State-machine cascade"],
  },
  {
    href: "/officer",
    eyebrow: "03 — Authority",
    title: "Officer dashboard",
    body: "B-Form authorization, reissuance, full audit trail, district-level population analytics.",
    icon: ShieldCheck,
    hue: "oklch(0.75 0.14 280)",
    bullets: ["Verify · Reject · Flag", "Reissue with reason", "Province × district stats"],
  },
  {
    href: "/dev",
    eyebrow: "04 — Transparency",
    title: "Database observatory",
    body: "Live query feed, interactive ER diagram, trigger lab. Every screen is a database lecture.",
    icon: Database,
    hue: "oklch(0.78 0.12 80)",
    bullets: ["Realtime query log", "Interactive triggers", "EXPLAIN traces"],
  },
];

const fadeUp = {
  hidden: { opacity: 0, y: 24 },
  show: { opacity: 1, y: 0 },
};

const stagger = {
  show: { transition: { staggerChildren: 0.07, delayChildren: 0.05 } },
};

export function PortalGrid() {
  return (
    <motion.section
      initial="hidden"
      whileInView="show"
      viewport={{ once: true, margin: "-80px" }}
      variants={stagger}
      className="mx-auto max-w-6xl px-6 pb-24"
    >
      <motion.h2
        variants={fadeUp}
        className="font-mono text-[10px] uppercase tracking-[0.25em] text-[var(--color-fg-subtle)]"
      >
        Four interfaces · One database
      </motion.h2>

      <div className="mt-6 grid gap-4 md:grid-cols-2">
        {CARDS.map((card) => (
          <PortalCard key={card.href} card={card} />
        ))}
      </div>
    </motion.section>
  );
}

function PortalCard({ card }: { card: Card }) {
  const Icon = card.icon;
  return (
    <motion.div variants={fadeUp}>
      <Link
        href={card.href}
        className="lift group relative block overflow-hidden rounded-3xl"
      >
        <div
          aria-hidden
          className="pointer-events-none absolute -inset-px opacity-0 blur-2xl transition-opacity duration-500 group-hover:opacity-100"
          style={{
            background: `radial-gradient(ellipse at top left, ${card.hue} / 0.4, transparent 60%)`,
          }}
        />
        <div className="glass glass-highlight relative h-full rounded-3xl p-7">
          <div className="flex items-start justify-between">
            <div
              className="flex size-12 items-center justify-center rounded-2xl text-[var(--color-fg)]"
              style={{
                background: `linear-gradient(135deg, ${card.hue} / 0.18, transparent)`,
                border: `1px solid ${card.hue} / 0.25`,
              }}
            >
              <Icon className="size-5" style={{ color: card.hue }} />
            </div>
            <ArrowUpRight className="size-4 text-[var(--color-fg-subtle)] transition-all group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-[var(--color-fg)]" />
          </div>

          <div className="mt-6 font-mono text-[10px] uppercase tracking-[0.22em] text-[var(--color-fg-subtle)]">
            {card.eyebrow}
          </div>

          <h3 className="font-display mt-2 text-2xl font-light tracking-tight md:text-3xl">
            {card.title}
          </h3>

          <p className="mt-3 max-w-sm text-sm leading-relaxed text-[var(--color-fg-muted)]">
            {card.body}
          </p>

          <ul className="mt-5 flex flex-wrap gap-1.5">
            {card.bullets.map((b) => (
              <li
                key={b}
                className="rounded-full border border-[var(--glass-border)] bg-[var(--glass-bg)] px-2.5 py-1 font-mono text-[10px] text-[var(--color-fg-muted)]"
              >
                {b}
              </li>
            ))}
          </ul>
        </div>
      </Link>
    </motion.div>
  );
}
