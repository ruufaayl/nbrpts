import Link from "next/link";
import { Hero } from "./_components/hero";
import { PortalGrid } from "./_components/portal-grid";
import { FlowDiagram } from "./_components/flow-diagram";

export default function Home() {
  return (
    <main className="relative">
      <Hero />
      <PortalGrid />
      <FlowDiagram />

      <footer className="mx-auto max-w-6xl px-6 pb-16">
        <div className="glass rounded-2xl px-6 py-5 text-sm leading-relaxed text-[var(--color-fg-muted)]">
          A semester project for{" "}
          <span className="text-[var(--color-fg)]">CS2013 — Introduction to Database Systems</span>.
          Built with Next.js 16, Supabase Postgres, and a deterministic
          rules-based verification layer. Schema in 3NF. Every screen, every
          portal, every query observable.{" "}
          <Link href="/dev" className="text-[var(--color-accent)] underline-offset-4 hover:underline">
            See the live database observatory →
          </Link>
        </div>
      </footer>
    </main>
  );
}
