"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import { ArrowRight, Code2 } from "lucide-react";

const fadeUp = {
  hidden: { opacity: 0, y: 18 },
  show: { opacity: 1, y: 0 },
};

const stagger = {
  show: { transition: { staggerChildren: 0.08, delayChildren: 0.2 } },
};

export function Hero() {
  return (
    <motion.section
      initial="hidden"
      animate="show"
      variants={stagger}
      className="relative mx-auto max-w-6xl px-6 pt-24 pb-16 md:pt-32 md:pb-24"
    >
      <motion.div
        variants={fadeUp}
        className="inline-flex items-center gap-2 rounded-full border border-[var(--glass-border)] bg-[var(--glass-bg)] px-3 py-1 font-mono text-[10px] uppercase tracking-[0.2em] text-[var(--color-fg-muted)] backdrop-blur"
      >
        <span className="size-1.5 rounded-full bg-[var(--color-accent)] shadow-[0_0_12px_var(--color-accent-glow)]" />
        CS2013 · Spring 2026 · FAST-NUCES
      </motion.div>

      <motion.h1
        variants={fadeUp}
        className="font-display mt-6 max-w-4xl text-5xl font-light leading-[1.05] tracking-tight md:text-7xl"
      >
        Every Pakistani child,{" "}
        <span className="text-shimmer italic">registered</span>{" "}
        the day they're born.
      </motion.h1>

      <motion.p
        variants={fadeUp}
        className="mt-8 max-w-2xl text-base leading-relaxed text-[var(--color-fg-muted)] md:text-lg"
      >
        NBRPTS turns every registered hospital into a direct data-entry
        point for NADRA. Births stream in continuously, an AI engine
        verifies them in real time, and B-Forms are ready for collection
        before parents leave the hospital.
      </motion.p>

      <motion.div variants={fadeUp} className="mt-10 flex flex-wrap items-center gap-3">
        <Link
          href="/dev"
          className="group accent-glow inline-flex items-center gap-2 rounded-full px-6 py-3 text-sm font-medium text-[var(--color-accent-fg)] transition hover:scale-[1.02]"
          style={{
            background: "linear-gradient(135deg, var(--color-accent), var(--color-accent-strong))",
          }}
        >
          Open the database observatory
          <ArrowRight className="size-4 transition group-hover:translate-x-0.5" />
        </Link>
        <a
          href="https://github.com/ruufaayl/nbrpts"
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-2 rounded-full border border-[var(--glass-border)] bg-[var(--glass-bg)] px-6 py-3 text-sm font-medium text-[var(--color-fg)] backdrop-blur transition hover:border-[var(--glass-border-strong)]"
        >
          <Code2 className="size-4" />
          View on GitHub
        </a>
      </motion.div>

      <motion.div
        variants={fadeUp}
        className="mt-16 grid gap-3 md:grid-cols-4 md:gap-6"
      >
        <Stat label="Tables in 3NF"      value="13" />
        <Stat label="Triggers"           value="8" />
        <Stat label="Business RPCs"      value="20+" />
        <Stat label="Migrations"         value="19" />
      </motion.div>
    </motion.section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="glass glass-highlight rounded-2xl px-5 py-4">
      <div className="font-display text-3xl font-light tracking-tight md:text-4xl">
        {value}
      </div>
      <div className="mt-1 font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--color-fg-subtle)]">
        {label}
      </div>
    </div>
  );
}
