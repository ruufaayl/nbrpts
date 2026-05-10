import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { RecordDetail } from "@/lib/officer/types";
import { StatusBadge } from "../../_components/status-badge";
import { RecordActions } from "./actions-client";

export const dynamic = "force-dynamic";

async function loadDetail(brn: string): Promise<RecordDetail | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_officer_record_detail", { p_brn: brn });
  if (error) {
    console.error("[officer/record]", error.message);
    return null;
  }
  return data as RecordDetail;
}

export default async function OfficerRecordPage({
  params,
}: {
  params: Promise<{ brn: string }>;
}) {
  const { brn: brnParam } = await params;
  const brn = decodeURIComponent(brnParam);
  const detail = await loadDetail(brn);

  if (!detail) {
    return (
      <main className="mx-auto max-w-4xl px-6 py-16">
        <Link href="/officer/queue" className="inline-flex items-center gap-2 text-sm text-[var(--color-fg-muted)]">
          <ArrowLeft className="size-4" /> Back to queue
        </Link>
        <div className="mt-8 rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] px-6 py-16 text-center">
          <p className="text-sm text-[var(--color-fg-muted)]">
            Birth record <code className="font-mono text-[var(--color-fg)]">{brn}</code> was not found.
          </p>
        </div>
      </main>
    );
  }

  const r = detail.record;

  return (
    <main className="mx-auto max-w-5xl px-6 py-10">
      <Link href="/officer/queue" className="inline-flex items-center gap-2 text-sm text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]">
        <ArrowLeft className="size-4" /> Back to queue
      </Link>

      <div className="mt-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="font-mono text-2xl text-[var(--color-fg)]">{r.brn}</h1>
            <StatusBadge status={r.status} />
          </div>
          <p className="mt-1 text-sm text-[var(--color-fg-muted)]">
            Submitted {new Date(r.submitted_at).toLocaleString()} from{" "}
            <span className="text-[var(--color-fg)]">{detail.hospital.hospital_name}</span>
          </p>
        </div>
        <RecordActions brn={r.brn} status={r.status} />
      </div>

      <div className="mt-8 grid gap-6 lg:grid-cols-2">
        <Card title="Birth">
          <Field label="Date / time" value={new Date(r.birth_datetime).toLocaleString()} />
          <Field label="Delivery type" value={r.delivery_type} />
          <Field label="Weight" value={`${r.birth_weight_kg} kg`} />
          <Field label="Outcome" value={r.birth_outcome} />
          <Field label="Doctor" value={`${r.attending_doctor} (${r.doctor_license_no})`} />
          <Field label="Child" value={`${r.child_full_name ?? "(unnamed)"} · ${r.child_gender ?? "—"}`} />
          {r.remarks ? <Field label="Remarks" value={r.remarks} /> : null}
        </Card>

        <Card title="Hospital">
          <Field label="Name" value={detail.hospital.hospital_name} />
          <Field label="HRN" value={detail.hospital.hrn} mono />
          <Field label="Type" value={detail.hospital.hospital_type} />
          <Field label="Location" value={`${detail.hospital.district}, ${detail.hospital.province}`} />
          <Field label="Contact" value={detail.hospital.contact_number} />
        </Card>

        <Card title="Mother">
          <Field label="Full name" value={detail.mother.full_name} />
          <Field label="CNIC" value={detail.mother.cnic ?? "(temp)"} mono />
          <Field label="Date of birth" value={detail.mother.date_of_birth} />
          <Field label="Contact" value={detail.mother.contact_number} />
          <Field label="Address" value={`${detail.mother.address}, ${detail.mother.district}, ${detail.mother.province}`} />
          {detail.mother.blood_group ? <Field label="Blood group" value={detail.mother.blood_group} /> : null}
        </Card>

        <Card title="Father">
          {detail.father ? (
            <>
              <Field label="Full name" value={detail.father.full_name} />
              <Field label="CNIC" value={detail.father.cnic ?? "—"} mono />
              <Field label="Date of birth" value={detail.father.date_of_birth} />
              <Field label="Contact" value={detail.father.contact_number} />
            </>
          ) : (
            <p className="text-sm text-[var(--color-fg-subtle)]">Not provided.</p>
          )}
        </Card>

        {detail.child ? (
          <Card title="Child (post-verification)">
            <Field label="CNIN" value={detail.child.cnin} mono accent />
            <Field label="Full name" value={detail.child.full_name} />
            <Field label="Gender" value={detail.child.gender} />
            <Field label="Date of birth" value={detail.child.date_of_birth} />
            <Field label="Created at" value={new Date(detail.child.created_at).toLocaleString()} />
          </Card>
        ) : null}

        {detail.bform ? (
          <Card title="B-Form">
            <Field label="Number" value={detail.bform.bform_number} mono accent />
            <Field label="Version" value={String(detail.bform.version)} />
            <Field label="Issue date" value={detail.bform.issue_date} />
            <Field
              label="Authorized"
              value={
                detail.bform.authorized_at
                  ? new Date(detail.bform.authorized_at).toLocaleString()
                  : "Pending authorization"
              }
            />
            {detail.bform.issued_by_name ? (
              <Field label="Issued by" value={detail.bform.issued_by_name} />
            ) : null}
            {detail.bform.reissue_reason ? (
              <Field label="Reissue reason" value={detail.bform.reissue_reason} />
            ) : null}
          </Card>
        ) : null}
      </div>

      {detail.ai_history.length > 0 ? (
        <section className="mt-12">
          <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
            AI review history
          </h2>
          <ul className="mt-3 divide-y divide-[var(--color-border)]/60 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
            {detail.ai_history.map((a) => (
              <li key={a.review_id} className="flex items-center justify-between gap-4 px-4 py-3">
                <div className="flex items-center gap-3">
                  <span
                    className={
                      "rounded px-1.5 py-0.5 font-mono text-[10px] uppercase " +
                      (a.verdict === "PASS"
                        ? "bg-[var(--color-accent)]/15 text-[var(--color-accent)]"
                        : a.verdict === "FLAG"
                          ? "bg-[var(--color-warn)]/15 text-[var(--color-warn)]"
                          : "bg-[var(--color-danger)]/15 text-[var(--color-danger)]")
                    }
                  >
                    {a.verdict}
                  </span>
                  <span className="font-mono text-xs text-[var(--color-fg-muted)]">
                    confidence {a.confidence_score ? Number(a.confidence_score).toFixed(3) : "—"}
                  </span>
                  {a.human_override ? (
                    <span className="rounded bg-[var(--color-fg)]/10 px-1.5 py-0.5 font-mono text-[10px] uppercase text-[var(--color-fg-muted)]">
                      override
                    </span>
                  ) : null}
                </div>
                <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                  {new Date(a.reviewed_at).toLocaleString()}
                </span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {detail.verification_log.length > 0 ? (
        <section className="mt-12">
          <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
            Verification log ({detail.verification_log.length})
          </h2>
          <ul className="mt-3 divide-y divide-[var(--color-border)]/60 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
            {detail.verification_log.map((v) => (
              <li key={v.log_id} className="px-4 py-3">
                <div className="flex items-center justify-between gap-4">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                      {v.action}
                    </span>
                    <StatusBadge status={v.previous_status} />
                    <span className="text-xs text-[var(--color-fg-subtle)]">→</span>
                    <StatusBadge status={v.new_status} />
                    <span className="text-xs text-[var(--color-fg-muted)]">
                      {v.officer_name ?? "—"}{" "}
                      <code className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                        {v.employee_no}
                      </code>
                    </span>
                  </div>
                  <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                    {new Date(v.action_datetime).toLocaleString()}
                  </span>
                </div>
                {v.remarks ? (
                  <p className="mt-1 text-xs text-[var(--color-fg-muted)]">{v.remarks}</p>
                ) : null}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-5">
      <h3 className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {title}
      </h3>
      <dl className="mt-3 grid gap-2">{children}</dl>
    </div>
  );
}

function Field({ label, value, mono, accent }: { label: string; value: string; mono?: boolean; accent?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 border-b border-[var(--color-border)]/40 py-1.5 last:border-0">
      <dt className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {label}
      </dt>
      <dd
        className={
          (mono ? "font-mono text-xs " : "text-sm ") +
          (accent ? "text-[var(--color-accent)]" : "text-[var(--color-fg)]")
        }
      >
        {value}
      </dd>
    </div>
  );
}
