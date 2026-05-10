"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Mail, Lock, Loader2, ArrowRight } from "lucide-react";
import { signInAction } from "./actions";

export function LoginForm({
  next,
  initialError,
}: {
  next?: string;
  initialError?: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | undefined>(initialError);
  const [email, setEmail] = useState("aisha@nbrpts.demo");
  const [password, setPassword] = useState("demo1234");

  function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setError(undefined);
    const fd = new FormData(e.currentTarget);
    startTransition(async () => {
      const r = await signInAction(fd);
      if (r?.error) setError(r.error);
      // success: signInAction redirects, no need to do anything here
      router.refresh();
    });
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5">
      <div>
        <h2 className="text-2xl font-medium tracking-tight">Welcome back</h2>
        <p className="mt-1 text-sm text-[var(--color-fg-muted)]">
          Use the credentials on the left, or your own if you have an account.
        </p>
      </div>

      <input type="hidden" name="next" value={next ?? "/dev/triggers"} />

      <Field
        icon={<Mail className="size-4" />}
        label="Email"
        type="email"
        name="email"
        value={email}
        onChange={setEmail}
        placeholder="you@example.com"
        autoComplete="email"
        required
      />

      <Field
        icon={<Lock className="size-4" />}
        label="Password"
        type="password"
        name="password"
        value={password}
        onChange={setPassword}
        placeholder="••••••••"
        autoComplete="current-password"
        required
      />

      {error && (
        <div className="rounded-lg border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 px-3 py-2 text-xs text-[var(--color-fg)]">
          {error}
        </div>
      )}

      <button
        type="submit"
        disabled={pending}
        className="group inline-flex w-full items-center justify-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:opacity-60"
      >
        {pending ? (
          <Loader2 className="size-4 animate-spin" />
        ) : (
          <>
            Sign in
            <ArrowRight className="size-4 transition group-hover:translate-x-0.5" />
          </>
        )}
      </button>
    </form>
  );
}

type FieldProps = Omit<
  React.InputHTMLAttributes<HTMLInputElement>,
  "onChange" | "value"
> & {
  icon: React.ReactNode;
  label: string;
  value: string;
  onChange: (v: string) => void;
};

function Field({ icon, label, value, onChange, ...rest }: FieldProps) {
  return (
    <label className="block">
      <span className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {label}
      </span>
      <div className="mt-1.5 flex items-center gap-2 rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 transition focus-within:border-[var(--color-accent)]">
        <span className="text-[var(--color-fg-subtle)]">{icon}</span>
        <input
          {...rest}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="w-full bg-transparent text-sm text-[var(--color-fg)] outline-none placeholder:text-[var(--color-fg-subtle)]"
        />
      </div>
    </label>
  );
}
