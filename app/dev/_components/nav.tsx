import Link from "next/link";
import { ArrowLeft, Activity } from "lucide-react";

type NavItem = { href: string; label: string };

const items: NavItem[] = [
  { href: "/dev", label: "Query feed" },
  { href: "/dev/schema", label: "Schema" },
];

export function DevNav({ active }: { active: NavItem["href"] }) {
  return (
    <div className="border-b border-[var(--color-border)]">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-4 px-6 py-4">
        <Link
          href="/"
          className="inline-flex items-center gap-2 text-sm text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
        >
          <ArrowLeft className="size-4" />
          Back
        </Link>

        <nav className="flex items-center gap-1 rounded-full border border-[var(--color-border)] p-1">
          {items.map((item) => {
            const isActive = item.href === active;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={
                  isActive
                    ? "rounded-full bg-[var(--color-bg-card)] px-3 py-1 text-xs font-medium text-[var(--color-fg)]"
                    : "rounded-full px-3 py-1 text-xs text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
                }
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-2 font-mono text-xs uppercase tracking-widest text-[var(--color-fg-muted)]">
          <Activity className="size-3.5 text-[var(--color-accent)]" />
          Database Observatory
        </div>
      </div>
    </div>
  );
}
