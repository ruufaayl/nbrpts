"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus, CheckCircle2, FileCheck2, RefreshCw, Loader2 } from "lucide-react";
import { toast } from "sonner";
import type {
  CurrentBformOption,
  PendingBformOption,
  PendingBirthOption,
} from "@/lib/domain/types";
import {
  authorizeAction,
  reissueAction,
  submitDemoRecordAction,
  verifyAction,
} from "./actions";

type Officer = {
  officer_id: string;
  full_name: string;
  employee_no: string;
};

type Props = {
  data: {
    pending: PendingBirthOption[];
    pendingBforms: PendingBformOption[];
    currentBforms: CurrentBformOption[];
    officers: Officer[];
  };
};

export function TriggerLab({ data }: Props) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  const officers = data.officers;
  const defaultOfficer = officers[0]?.officer_id ?? "";

  const [verifyId, setVerifyId] = useState(data.pending[0]?.birth_record_id ?? "");
  const [verifyOfficer, setVerifyOfficer] = useState(defaultOfficer);

  const [authBformId, setAuthBformId] = useState(
    data.pendingBforms[0]?.bform_id ?? ""
  );
  const [authOfficer, setAuthOfficer] = useState(defaultOfficer);

  const [reissueChild, setReissueChild] = useState(
    data.currentBforms[0]?.child_id ?? ""
  );
  const [reissueOfficer, setReissueOfficer] = useState(defaultOfficer);
  const [reissueReason, setReissueReason] = useState("Lost original document");

  function run<T extends { ok: boolean; message?: string; error?: string }>(
    fn: () => Promise<T>
  ) {
    startTransition(async () => {
      const r = await fn();
      if (r.ok) {
        toast.success(r.message ?? "Done");
      } else {
        toast.error(r.error ?? "Action failed");
      }
      router.refresh();
    });
  }

  return (
    <div className="mt-10 grid gap-4 md:grid-cols-2">
      {/* Card 1: Submit demo record */}
      <Card
        icon={<Plus className="size-4" />}
        title="Submit a demo birth record"
        body="Calls submit_birth_record() with a random mother and a known hospital. The new record lands in PENDING."
      >
        <div className="text-xs text-[var(--color-fg-subtle)]">
          No options — fires the RPC with sensible defaults.
        </div>
        <ActionButton
          pending={pending}
          onClick={() => run(submitDemoRecordAction)}
        >
          Submit
        </ActionButton>
      </Card>

      {/* Card 2: Verify a record */}
      <Card
        icon={<CheckCircle2 className="size-4" />}
        title="Verify a record"
        body="Updates status PENDING/FLAGGED → VERIFIED. The trigger cascade creates a child (with CNIN), links guardians, generates a B-Form, and queues an SMS."
      >
        <Field label="Birth record">
          <Select
            value={verifyId}
            onChange={setVerifyId}
            empty="No PENDING/FLAGGED records — submit one first."
            options={data.pending.map((p) => ({
              value: p.birth_record_id,
              label: `${p.brn} · ${p.status} · ${p.mother_name}`,
            }))}
          />
        </Field>
        <Field label="Officer">
          <Select
            value={verifyOfficer}
            onChange={setVerifyOfficer}
            options={officers.map((o) => ({
              value: o.officer_id,
              label: `${o.full_name} (${o.employee_no})`,
            }))}
          />
        </Field>
        <ActionButton
          pending={pending}
          disabled={!verifyId || !verifyOfficer}
          onClick={() => run(() => verifyAction(verifyId, verifyOfficer))}
        >
          Verify (fires cascade)
        </ActionButton>
      </Card>

      {/* Card 3: Authorize B-Form */}
      <Card
        icon={<FileCheck2 className="size-4" />}
        title="Authorize a B-Form"
        body="Officer reviews a generated B-Form and authorizes it. The queued SMS flips to SENT and the body changes to 'ready for collection'."
      >
        <Field label="B-Form">
          <Select
            value={authBformId}
            onChange={setAuthBformId}
            empty="All B-Forms are authorized."
            options={data.pendingBforms.map((b) => ({
              value: b.bform_id,
              label: `${b.bform_number} · ${b.child_name}`,
            }))}
          />
        </Field>
        <Field label="Officer">
          <Select
            value={authOfficer}
            onChange={setAuthOfficer}
            options={officers.map((o) => ({
              value: o.officer_id,
              label: `${o.full_name} (${o.employee_no})`,
            }))}
          />
        </Field>
        <ActionButton
          pending={pending}
          disabled={!authBformId || !authOfficer}
          onClick={() => run(() => authorizeAction(authBformId, authOfficer))}
        >
          Authorize
        </ActionButton>
      </Card>

      {/* Card 4: Reissue B-Form */}
      <Card
        icon={<RefreshCw className="size-4" />}
        title="Reissue a B-Form"
        body="Increments version, marks the prior version is_current = false, queues a fresh SMS. The original is preserved — never deleted."
      >
        <Field label="Child">
          <Select
            value={reissueChild}
            onChange={setReissueChild}
            empty="No authorized B-Forms yet."
            options={data.currentBforms.map((b) => ({
              value: b.child_id,
              label: `${b.child_name} · v${b.version} · ${b.bform_number}`,
            }))}
          />
        </Field>
        <Field label="Officer">
          <Select
            value={reissueOfficer}
            onChange={setReissueOfficer}
            options={officers.map((o) => ({
              value: o.officer_id,
              label: `${o.full_name} (${o.employee_no})`,
            }))}
          />
        </Field>
        <Field label="Reason">
          <input
            value={reissueReason}
            onChange={(e) => setReissueReason(e.target.value)}
            className="w-full rounded-md border border-[var(--color-border)] bg-[var(--color-bg)] px-2.5 py-1.5 font-mono text-xs text-[var(--color-fg)] outline-none focus:border-[var(--color-accent)]"
          />
        </Field>
        <ActionButton
          pending={pending}
          disabled={!reissueChild || !reissueOfficer || !reissueReason.trim()}
          onClick={() =>
            run(() => reissueAction(reissueChild, reissueOfficer, reissueReason))
          }
        >
          Reissue
        </ActionButton>
      </Card>
    </div>
  );
}

function Card({
  icon,
  title,
  body,
  children,
}: {
  icon: React.ReactNode;
  title: string;
  body: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-5">
      <div className="flex items-center gap-2 text-[var(--color-accent)]">
        {icon}
        <span className="text-sm font-medium text-[var(--color-fg)]">
          {title}
        </span>
      </div>
      <p className="mt-2 text-xs leading-relaxed text-[var(--color-fg-muted)]">
        {body}
      </p>
      <div className="mt-4 space-y-3">{children}</div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {label}
      </span>
      <div className="mt-1">{children}</div>
    </label>
  );
}

function Select({
  value,
  onChange,
  options,
  empty,
}: {
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
  empty?: string;
}) {
  if (options.length === 0) {
    return (
      <div className="rounded-md border border-dashed border-[var(--color-border)] px-2.5 py-1.5 text-xs text-[var(--color-fg-muted)]">
        {empty ?? "No options."}
      </div>
    );
  }
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="w-full rounded-md border border-[var(--color-border)] bg-[var(--color-bg)] px-2.5 py-1.5 font-mono text-xs text-[var(--color-fg)] outline-none focus:border-[var(--color-accent)]"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

function ActionButton({
  pending,
  disabled,
  onClick,
  children,
}: {
  pending: boolean;
  disabled?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      disabled={pending || disabled}
      className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-[var(--color-accent)] px-4 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
    >
      {pending && <Loader2 className="size-4 animate-spin" />}
      {children}
    </button>
  );
}
