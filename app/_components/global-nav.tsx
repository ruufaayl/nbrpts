"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion } from "framer-motion";
import { Hospital, Brain, ShieldCheck, Database, Command } from "lucide-react";
import { useEffect, useState } from "react";

const NAV = [
  { href: "/hospital",  label: "Hospital",  icon: Hospital },
  { href: "/ai-engine", label: "AI",        icon: Brain },
  { href: "/officer",   label: "Officer",   icon: ShieldCheck },
  { href: "/dev",       label: "Observatory", icon: Database },
];

// Routes that own their own header (scoped portal layouts) or are the
// cinematic landing page where the global nav would interrupt the design.
const SCOPED_ROUTES = ["/hospital", "/officer", "/login"];
const HIDE_EXACT = new Set(["/"]);

export function GlobalNav() {
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  const [isMac, setIsMac] = useState(true);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    setIsMac(typeof navigator !== "undefined" && /Mac|iPhone|iPad/i.test(navigator.platform));
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  if (HIDE_EXACT.has(pathname)) return null;
  if (SCOPED_ROUTES.some((r) => pathname === r || pathname.startsWith(r + "/"))) {
    return null;
  }

  const openPalette = () => {
    if (typeof window === "undefined") return;
    window.dispatchEvent(
      new KeyboardEvent("keydown", { key: "k", metaKey: true, ctrlKey: true, bubbles: true }),
    );
  };

  return (
    <motion.header
      initial={{ y: -16, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.5, ease: [0.2, 0, 0, 1], delay: 0.1 }}
      className="sticky top-0 z-30 px-4 pt-3"
    >
      <div
        className={
          "mx-auto max-w-7xl rounded-full transition-all duration-300 " +
          (scrolled ? "glass glass-highlight" : "border border-transparent")
        }
      >
        <div className="flex items-center justify-between gap-4 px-4 py-2">
          <Link href="/" className="flex items-center gap-2.5">
            <div className="relative">
              <div
                className="flex size-7 items-center justify-center rounded-lg text-[var(--color-accent-fg)]"
                style={{
                  background: "linear-gradient(135deg, var(--color-accent), var(--color-accent-strong))",
                  boxShadow: "0 4px 16px -4px var(--color-accent-glow)",
                }}
              >
                <span className="font-display text-sm font-medium">N</span>
              </div>
            </div>
            <span className="font-display text-base tracking-tight">NBRPTS</span>
          </Link>

          <nav className="hidden items-center gap-1 md:flex">
            {NAV.map((item) => {
              const Icon = item.icon;
              const active = pathname === item.href || pathname.startsWith(item.href + "/");
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={
                    "relative inline-flex items-center gap-2 rounded-full px-3.5 py-1.5 text-xs font-medium transition " +
                    (active
                      ? "text-[var(--color-fg)]"
                      : "text-[var(--color-fg-muted)] hover:text-[var(--color-fg)]")
                  }
                >
                  {active ? (
                    <motion.span
                      layoutId="nav-pill"
                      className="absolute inset-0 rounded-full bg-[var(--glass-bg-strong)] ring-1 ring-[var(--glass-border-strong)]"
                      transition={{ type: "spring", stiffness: 380, damping: 30 }}
                    />
                  ) : null}
                  <span className="relative flex items-center gap-1.5">
                    <Icon className="size-3.5" />
                    {item.label}
                  </span>
                </Link>
              );
            })}
          </nav>

          <button
            type="button"
            onClick={openPalette}
            className="group inline-flex items-center gap-2 rounded-full border border-[var(--glass-border)] bg-[var(--glass-bg)] px-3 py-1.5 text-xs text-[var(--color-fg-muted)] transition hover:border-[var(--glass-border-strong)] hover:text-[var(--color-fg)]"
            aria-label="Open command palette"
          >
            <Command className="size-3.5" />
            <span className="hidden sm:inline">Jump</span>
            <kbd className="hidden rounded border border-[var(--glass-border)] bg-[var(--glass-bg-strong)] px-1.5 py-0.5 font-mono text-[10px] sm:inline-block">
              {isMac ? "⌘" : "Ctrl"} K
            </kbd>
          </button>
        </div>
      </div>
    </motion.header>
  );
}
