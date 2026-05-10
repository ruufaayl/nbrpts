import Link from "next/link";
import { ArrowUpRight, Database, Hospital, ShieldCheck } from "lucide-react";

export default function LandingPage() {
  return (
    <main className="relative min-h-screen overflow-hidden">
      <div className="absolute inset-0 bg-grid opacity-60" />
      <div className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-[var(--color-accent)] to-transparent opacity-50" />

      <div className="relative mx-auto max-w-6xl px-6 py-24 md:py-32">
        <div className="flex items-center gap-2 text-xs font-mono uppercase tracking-widest text-[var(--color-fg-muted)]">
          <span className="size-1.5 rounded-full bg-[var(--color-accent)] animate-pulse" />
          CS2013 · Spring 2026 · FAST-NUCES
        </div>

        <h1 className="mt-6 max-w-3xl text-balance text-5xl font-medium leading-[1.05] tracking-tight md:text-7xl">
          Every Pakistani child,{" "}
          <span className="text-[var(--color-fg-muted)]">registered</span>{" "}
          the day they&rsquo;re born.
        </h1>

        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-[var(--color-fg-muted)]">
          NBRPTS turns every registered hospital into a direct data-entry point
          for NADRA. Births stream in continuously, AI verifies them in real
          time, and B-Forms are ready for collection before the parents leave
          the hospital.
        </p>

        <div className="mt-10 flex flex-wrap items-center gap-3">
          <Link
            href="/dev"
            className="group inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90"
          >
            Open the database observatory
            <ArrowUpRight className="size-4 transition group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />
          </Link>
          <a
            href="https://github.com/ruufaayl/nbrpts"
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 rounded-full border border-[var(--color-border)] px-5 py-2.5 text-sm font-medium text-[var(--color-fg)] transition hover:border-[var(--color-border-strong)]"
          >
            View source on GitHub
          </a>
        </div>

        <div className="mt-24 grid gap-px overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-border)] md:grid-cols-3">
          <Pillar
            href="/hospital"
            icon={<Hospital className="size-5" />}
            title="Hospital portal"
            body="Offline-first birth-record entry. Auto-syncs when connectivity returns. Tamper-proof local storage."
          />
          <Pillar
            href="/ai-engine"
            icon={<ShieldCheck className="size-5" />}
            title="AI verification"
            body="Eight rules, real-time JSON verdicts, auto-approve on high confidence, human review on flags."
          />
          <Pillar
            href="/officer"
            icon={<Database className="size-5" />}
            title="Officer dashboard"
            body="B-Form authorization, reissuance, full audit trail, district-level population analytics."
          />
        </div>

        <p className="mt-24 max-w-xl text-sm leading-relaxed text-[var(--color-fg-subtle)]">
          A semester project for CS2013 — Introduction to Database Systems.
          Built with Next.js, Supabase Postgres, and an LLM-powered verification
          layer. Schema in 3NF. Every screen, every portal, every query
          observable.
        </p>
      </div>
    </main>
  );
}

function Pillar({
  href,
  icon,
  title,
  body,
}: {
  href: string;
  icon: React.ReactNode;
  title: string;
  body: string;
}) {
  return (
    <Link
      href={href}
      className="group block bg-[var(--color-bg)] p-6 transition hover:bg-[var(--color-bg-elev)]"
    >
      <div className="flex size-10 items-center justify-center rounded-lg bg-[var(--color-bg-card)] text-[var(--color-accent)]">
        {icon}
      </div>
      <div className="mt-5 text-base font-medium transition group-hover:text-[var(--color-accent)]">
        {title}
      </div>
      <div className="mt-2 text-sm leading-relaxed text-[var(--color-fg-muted)]">
        {body}
      </div>
    </Link>
  );
}
