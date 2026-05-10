import { redirect } from "next/navigation";
import Link from "next/link";
import { LogOut, Hospital, FileText, Inbox, Cpu } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import { signOutAction } from "@/app/dev/triggers/actions";

type Whoami = {
  signed_in: boolean;
  email?: string;
  role?: string;
  full_name?: string;
  hospital_name?: string;
};

export default async function HospitalLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await getSupabaseServer();
  const { data: who } = await supabase.rpc("whoami");
  const me = (who as Whoami) ?? { signed_in: false };

  if (!me.signed_in) {
    redirect("/login?next=/hospital");
  }
  if (me.role !== "hospital_staff") {
    return (
      <main className="min-h-screen">
        <div className="mx-auto max-w-3xl px-6 py-24">
          <div className="rounded-2xl border border-[var(--color-warn)]/40 bg-[var(--color-warn)]/10 p-8">
            <h1 className="text-2xl font-medium">Hospital portal</h1>
            <p className="mt-3 text-sm text-[var(--color-fg-muted)]">
              You're signed in as <span className="font-mono text-[var(--color-fg)]">{me.role}</span>,
              but this portal is only available to <span className="font-mono">hospital_staff</span>.
              Sign in as <code className="font-mono">aku@nbrpts.demo</code> to try it.
            </p>
            <form action={signOutAction} className="mt-6">
              <button className="inline-flex items-center gap-2 rounded-full border border-[var(--color-border)] px-4 py-2 text-sm transition hover:border-[var(--color-border-strong)]">
                <LogOut className="size-4" />
                Sign out and switch
              </button>
            </form>
          </div>
        </div>
      </main>
    );
  }

  return (
    <div className="min-h-screen">
      <header className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)]">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4 px-6 py-4">
          <Link href="/hospital" className="flex items-center gap-3">
            <div className="flex size-9 items-center justify-center rounded-lg bg-[var(--color-accent)]/10 text-[var(--color-accent)]">
              <Hospital className="size-5" />
            </div>
            <div>
              <div className="text-sm font-medium text-[var(--color-fg)]">
                {me.hospital_name ?? "Hospital portal"}
              </div>
              <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                Hospital Staff Console
              </div>
            </div>
          </Link>

          <PortalNav />

          <div className="flex items-center gap-3 font-mono text-xs">
            <span className="text-[var(--color-fg-muted)]">{me.full_name}</span>
            <form action={signOutAction}>
              <button
                type="submit"
                className="inline-flex items-center gap-1.5 rounded-full border border-[var(--color-border)] px-3 py-1 text-[var(--color-fg-muted)] transition hover:border-[var(--color-border-strong)] hover:text-[var(--color-fg)]"
              >
                <LogOut className="size-3" />
                Sign out
              </button>
            </form>
          </div>
        </div>
      </header>

      {children}
    </div>
  );
}

function PortalNav() {
  const items = [
    { href: "/hospital",             label: "Dashboard",   icon: Hospital },
    { href: "/hospital/submit",      label: "Submit",      icon: FileText },
    { href: "/hospital/submissions", label: "Submissions", icon: Inbox },
    { href: "/hospital/device",      label: "Device",      icon: Cpu },
  ];
  return (
    <nav className="flex items-center gap-1 rounded-full border border-[var(--color-border)] bg-[var(--color-bg)] p-1">
      {items.map((item) => {
        const Icon = item.icon;
        return (
          <Link
            key={item.href}
            href={item.href}
            className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs text-[var(--color-fg-muted)] transition hover:bg-[var(--color-bg-elev)] hover:text-[var(--color-fg)]"
          >
            <Icon className="size-3.5" />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
