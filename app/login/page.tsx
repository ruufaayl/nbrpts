import Link from "next/link";
import { redirect } from "next/navigation";
import { ArrowLeft, ShieldCheck } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import { LoginForm } from "./login-form";

export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; error?: string }>;
}) {
  const { next, error } = await searchParams;

  const supabase = await getSupabaseServer();
  const { data } = await supabase.auth.getUser();
  if (data.user) {
    redirect(next ?? "/dev/triggers");
  }

  return (
    <main className="relative min-h-screen overflow-hidden">
      <div className="absolute inset-0 bg-grid opacity-50" />
      <div className="relative mx-auto flex min-h-screen max-w-6xl flex-col px-6 py-8">
        <div>
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-sm text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
          >
            <ArrowLeft className="size-4" />
            Back to home
          </Link>
        </div>

        <div className="mt-12 grid flex-1 items-start gap-12 md:mt-24 md:grid-cols-2 md:gap-16">
          <div className="max-w-md">
            <div className="flex items-center gap-2 font-mono text-xs uppercase tracking-widest text-[var(--color-fg-muted)]">
              <ShieldCheck className="size-3.5 text-[var(--color-accent)]" />
              NBRPTS Authentication
            </div>
            <h1 className="mt-6 text-balance text-4xl font-medium leading-tight tracking-tight md:text-5xl">
              Sign in to the
              <br />
              <span className="text-[var(--color-fg-muted)]">birth registry.</span>
            </h1>
            <p className="mt-6 text-sm leading-relaxed text-[var(--color-fg-muted)]">
              Three roles, one login: hospital staff submit births, NADRA
              officers verify and authorize, admins oversee the entire pipeline.
              Row-Level Security on every table scopes what you see.
            </p>

            <div className="mt-10 rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-5">
              <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                Demo credentials
              </div>
              <div className="mt-3 space-y-2 font-mono text-xs">
                <DemoCred role="admin"          email="admin@nbrpts.demo" />
                <DemoCred role="nadra_officer"  email="aisha@nbrpts.demo" />
                <DemoCred role="hospital_staff" email="aku@nbrpts.demo"   />
              </div>
              <div className="mt-3 text-[11px] text-[var(--color-fg-subtle)]">
                Password for all three: <code className="text-[var(--color-fg)]">demo1234</code>
              </div>
            </div>
          </div>

          <div className="rounded-3xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-6 md:p-10">
            <LoginForm next={next} initialError={error} />
          </div>
        </div>
      </div>
    </main>
  );
}

function DemoCred({ role, email }: { role: string; email: string }) {
  return (
    <div className="flex items-center justify-between gap-3 rounded-md bg-[var(--color-bg)] px-3 py-2">
      <span className="text-[var(--color-accent)]">{role}</span>
      <span className="truncate text-[var(--color-fg)]">{email}</span>
    </div>
  );
}
