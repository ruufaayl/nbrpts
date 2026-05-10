import Link from "next/link";
import { ArrowLeft, Activity, LogOut, LogIn } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import { signOutAction } from "@/app/dev/triggers/actions";

type NavItem = { href: string; label: string };

const items: NavItem[] = [
  { href: "/dev", label: "Query feed" },
  { href: "/dev/schema", label: "Schema" },
  { href: "/dev/triggers", label: "Triggers" },
];

type Whoami = {
  signed_in: boolean;
  email?: string;
  role?: "admin" | "nadra_officer" | "hospital_staff";
  full_name?: string;
  hospital_name?: string;
  officer_name?: string;
  office_name?: string;
};

async function whoami(): Promise<Whoami> {
  const supabase = await getSupabaseServer();
  const { data } = await supabase.rpc("whoami");
  return (data as Whoami) ?? { signed_in: false };
}

export async function DevNav({ active }: { active: NavItem["href"] }) {
  const me = await whoami();

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

        <div className="flex items-center gap-3 font-mono text-xs uppercase tracking-widest text-[var(--color-fg-muted)]">
          <Activity className="size-3.5 text-[var(--color-accent)]" />
          <span className="hidden sm:inline">Database Observatory</span>
        </div>
      </div>

      <UserStrip me={me} />
    </div>
  );
}

function UserStrip({ me }: { me: Whoami }) {
  if (!me.signed_in) {
    return (
      <div className="border-t border-[var(--color-border)] bg-[var(--color-bg-elev)]">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-6 py-2 font-mono text-[11px] text-[var(--color-fg-muted)]">
          <span>
            Acting as <span className="text-[var(--color-fg)]">anonymous</span>
            <span className="ml-2 text-[var(--color-fg-subtle)]">
              · all reads via SECURITY DEFINER RPCs
            </span>
          </span>
          <Link
            href="/login"
            className="inline-flex items-center gap-1.5 rounded-full bg-[var(--color-accent)]/10 px-3 py-1 text-[var(--color-accent)] transition hover:bg-[var(--color-accent)]/20"
          >
            <LogIn className="size-3" />
            Sign in
          </Link>
        </div>
      </div>
    );
  }

  const scope =
    me.role === "admin"
      ? "Admin · sees everything"
      : me.role === "nadra_officer"
        ? `${me.officer_name} · ${me.office_name ?? ""}`
        : `${me.hospital_name ?? "Hospital"} staff`;

  return (
    <div className="border-t border-[var(--color-border)] bg-[var(--color-bg-elev)]">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-6 py-2 font-mono text-[11px] text-[var(--color-fg-muted)]">
        <span>
          Acting as <span className="text-[var(--color-accent)]">{me.role}</span>
          <span className="mx-2 text-[var(--color-fg-subtle)]">·</span>
          <span className="text-[var(--color-fg)]">{me.full_name}</span>
          <span className="mx-2 text-[var(--color-fg-subtle)]">·</span>
          <span className="text-[var(--color-fg-muted)]">{scope}</span>
        </span>
        <form action={signOutAction}>
          <button
            type="submit"
            className="inline-flex items-center gap-1.5 rounded-full border border-[var(--color-border)] px-3 py-1 transition hover:border-[var(--color-border-strong)] hover:text-[var(--color-fg)]"
          >
            <LogOut className="size-3" />
            Sign out
          </button>
        </form>
      </div>
    </div>
  );
}
