import { SubmitForm } from "./form";

export const dynamic = "force-dynamic";

export default function SubmitPage() {
  return (
    <main className="mx-auto max-w-3xl px-6 py-10">
      <div>
        <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
          New birth record
        </h1>
        <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
          Four steps. The mother is matched by CNIC — if she's already
          registered with NADRA, we'll re-use her record. The submission lands
          in <code className="font-mono">PENDING</code> and the AI engine picks
          it up immediately.
        </p>
      </div>

      <div className="mt-10">
        <SubmitForm />
      </div>
    </main>
  );
}
