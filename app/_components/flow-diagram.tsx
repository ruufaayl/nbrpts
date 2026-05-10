"use client";

import { motion } from "framer-motion";
import { Hospital, Brain, ShieldCheck, FileCheck2, ArrowRight } from "lucide-react";

const STEPS = [
  { icon: Hospital,    label: "Hospital",   sub: "submits PENDING", hue: "oklch(0.78 0.16 158)" },
  { icon: Brain,       label: "AI Engine",  sub: "scores + transitions", hue: "oklch(0.7 0.16 220)" },
  { icon: ShieldCheck, label: "Officer",    sub: "reviews FLAGGED", hue: "oklch(0.75 0.14 280)" },
  { icon: FileCheck2,  label: "B-Form",     sub: "ready for parent", hue: "oklch(0.78 0.18 78)" },
];

export function FlowDiagram() {
  return (
    <motion.section
      initial={{ opacity: 0, y: 24 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-100px" }}
      transition={{ duration: 0.6, ease: [0.2, 0, 0, 1] }}
      className="mx-auto max-w-6xl px-6 pb-24"
    >
      <h2 className="font-mono text-[10px] uppercase tracking-[0.25em] text-[var(--color-fg-subtle)]">
        End-to-end pipeline
      </h2>
      <p className="font-display mt-3 max-w-3xl text-2xl font-light tracking-tight md:text-3xl">
        From the delivery room to the parent's hand —{" "}
        <span className="text-[var(--color-accent)]">in under 60 seconds</span>.
      </p>

      <div className="glass glass-highlight mt-10 rounded-3xl p-8">
        <ol className="grid items-stretch gap-3 md:grid-cols-7 md:gap-0">
          {STEPS.map((step, i) => {
            const Icon = step.icon;
            return (
              <motion.li
                key={step.label}
                initial={{ opacity: 0, scale: 0.9 }}
                whileInView={{ opacity: 1, scale: 1 }}
                viewport={{ once: true }}
                transition={{ delay: i * 0.08, duration: 0.4 }}
                className={
                  "contents " +
                  (i === STEPS.length - 1 ? "" : "")
                }
              >
                <div className="md:col-span-1">
                  <div className="flex flex-col items-center gap-3 px-2 py-3 text-center">
                    <div
                      className="flex size-12 items-center justify-center rounded-2xl"
                      style={{
                        background: `${step.hue} / 0.12`,
                        border: `1px solid ${step.hue} / 0.3`,
                        boxShadow: `0 0 24px -8px ${step.hue} / 0.5`,
                      }}
                    >
                      <Icon className="size-5" style={{ color: step.hue }} />
                    </div>
                    <div>
                      <div className="text-sm font-medium text-[var(--color-fg)]">{step.label}</div>
                      <div className="mt-0.5 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                        {step.sub}
                      </div>
                    </div>
                  </div>
                </div>
                {i < STEPS.length - 1 ? (
                  <div className="flex items-center justify-center md:col-span-1">
                    <div className="hidden h-px flex-1 bg-gradient-to-r from-[var(--glass-border)] via-[var(--color-accent)]/40 to-[var(--glass-border)] md:block" />
                    <ArrowRight className="size-4 text-[var(--color-fg-subtle)]" />
                    <div className="hidden h-px flex-1 bg-gradient-to-r from-[var(--glass-border)] via-[var(--color-accent)]/40 to-[var(--glass-border)] md:block" />
                  </div>
                ) : null}
              </motion.li>
            );
          })}
        </ol>
      </div>
    </motion.section>
  );
}
