"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowLeft, ArrowRight, CheckCircle2, Loader2, User, Users, Stethoscope, Eye } from "lucide-react";
import { toast } from "sonner";
import type { SubmitFormData } from "@/lib/hospital/types";
import { submitBirthRecordAction } from "./actions";

const initial: SubmitFormData = {
  mother_cnic: "",
  mother_full_name: "",
  mother_dob: "",
  mother_contact: "",
  mother_address: "",
  mother_province: "SINDH",
  mother_district: "Karachi-South",
  mother_blood_group: "",
  father_cnic: "",
  father_full_name: "",
  father_dob: "",
  father_contact: "",
  attending_doctor: "",
  doctor_license_no: "",
  birth_datetime: new Date(Date.now() - 1000 * 60 * 60).toISOString().slice(0, 16),
  delivery_type: "NORMAL",
  birth_weight_kg: "3.20",
  birth_outcome: "LIVE_BIRTH",
  child_gender: "MALE",
  child_full_name: "",
  remarks: "",
};

const steps = [
  { id: 0, label: "Mother",  icon: User },
  { id: 1, label: "Father",  icon: Users },
  { id: 2, label: "Birth",   icon: Stethoscope },
  { id: 3, label: "Review",  icon: Eye },
] as const;

export function SubmitForm() {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [form, setForm] = useState<SubmitFormData>(initial);
  const [pending, startTransition] = useTransition();

  function update<K extends keyof SubmitFormData>(key: K, value: SubmitFormData[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  function next() {
    setStep((s) => Math.min(s + 1, steps.length - 1));
  }
  function prev() {
    setStep((s) => Math.max(s - 1, 0));
  }

  function submit() {
    startTransition(async () => {
      const r = await submitBirthRecordAction(form);
      if (r.ok) {
        toast.success(`Submitted ${r.brn}. Status: PENDING.`);
        router.push("/hospital/submissions");
      } else {
        toast.error(r.error);
      }
    });
  }

  return (
    <div>
      <Stepper current={step} />

      <div className="mt-8 rounded-3xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-6 md:p-8">
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={step}
            initial={{ opacity: 0, x: 16 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -16 }}
            transition={{ duration: 0.18 }}
          >
            {step === 0 && <MotherStep form={form} update={update} />}
            {step === 1 && <FatherStep form={form} update={update} />}
            {step === 2 && <BirthStep form={form} update={update} />}
            {step === 3 && <ReviewStep form={form} />}
          </motion.div>
        </AnimatePresence>

        <div className="mt-8 flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={prev}
            disabled={step === 0 || pending}
            className="inline-flex items-center gap-2 rounded-full border border-[var(--color-border)] px-4 py-2 text-sm transition hover:border-[var(--color-border-strong)] disabled:opacity-40"
          >
            <ArrowLeft className="size-4" />
            Back
          </button>

          {step < steps.length - 1 ? (
            <button
              type="button"
              onClick={next}
              disabled={!isStepValid(step, form)}
              className="inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:opacity-50"
            >
              Continue
              <ArrowRight className="size-4" />
            </button>
          ) : (
            <button
              type="button"
              onClick={submit}
              disabled={pending}
              className="inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90 disabled:opacity-50"
            >
              {pending ? (
                <Loader2 className="size-4 animate-spin" />
              ) : (
                <CheckCircle2 className="size-4" />
              )}
              Submit to NADRA
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function isStepValid(step: number, f: SubmitFormData): boolean {
  if (step === 0) {
    return (
      /^[0-9]{5}-[0-9]{7}-[0-9]$/.test(f.mother_cnic) &&
      f.mother_full_name.trim().length > 0 &&
      !!f.mother_dob &&
      f.mother_contact.trim().length > 0 &&
      f.mother_address.trim().length > 0 &&
      f.mother_district.trim().length > 0
    );
  }
  if (step === 1) {
    if (f.father_cnic.trim() === "") return true;
    return (
      /^[0-9]{5}-[0-9]{7}-[0-9]$/.test(f.father_cnic) &&
      f.father_full_name.trim().length > 0 &&
      !!f.father_dob &&
      f.father_contact.trim().length > 0
    );
  }
  if (step === 2) {
    return (
      f.attending_doctor.trim().length > 0 &&
      /^PMDC-[0-9]{6}$/.test(f.doctor_license_no) &&
      !!f.birth_datetime &&
      Number(f.birth_weight_kg) >= 0.3 &&
      Number(f.birth_weight_kg) <= 7
    );
  }
  return true;
}

function Stepper({ current }: { current: number }) {
  return (
    <div className="flex items-center gap-2">
      {steps.map((s, i) => {
        const Icon = s.icon;
        const done = i < current;
        const active = i === current;
        return (
          <div key={s.id} className="flex items-center gap-2">
            <div
              className={
                "flex size-8 items-center justify-center rounded-full border transition " +
                (active
                  ? "border-[var(--color-accent)] bg-[var(--color-accent)] text-[var(--color-accent-fg)]"
                  : done
                    ? "border-[var(--color-accent)]/50 bg-[var(--color-accent)]/10 text-[var(--color-accent)]"
                    : "border-[var(--color-border)] text-[var(--color-fg-subtle)]")
              }
            >
              <Icon className="size-3.5" />
            </div>
            <div
              className={
                "font-mono text-[10px] uppercase tracking-widest " +
                (active ? "text-[var(--color-fg)]" : "text-[var(--color-fg-subtle)]")
              }
            >
              {s.label}
            </div>
            {i < steps.length - 1 && (
              <div className="mx-2 h-px w-6 bg-[var(--color-border)]" />
            )}
          </div>
        );
      })}
    </div>
  );
}

type StepProps = {
  form: SubmitFormData;
  update: <K extends keyof SubmitFormData>(k: K, v: SubmitFormData[K]) => void;
};

function MotherStep({ form, update }: StepProps) {
  return (
    <div>
      <h2 className="text-lg font-medium">Mother's details</h2>
      <p className="mt-1 text-xs text-[var(--color-fg-muted)]">
        If her CNIC is already registered with NADRA, we'll re-use the record.
      </p>
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <Field label="CNIC" hint="XXXXX-XXXXXXX-X">
          <Input value={form.mother_cnic} onChange={(v) => update("mother_cnic", v)} placeholder="42101-1234567-1" />
        </Field>
        <Field label="Full name">
          <Input value={form.mother_full_name} onChange={(v) => update("mother_full_name", v)} placeholder="Ayesha Siddiqui" />
        </Field>
        <Field label="Date of birth">
          <Input type="date" value={form.mother_dob} onChange={(v) => update("mother_dob", v)} />
        </Field>
        <Field label="Contact number">
          <Input value={form.mother_contact} onChange={(v) => update("mother_contact", v)} placeholder="+92-300-1234567" />
        </Field>
        <Field label="Address" full>
          <Input value={form.mother_address} onChange={(v) => update("mother_address", v)} placeholder="Block 6, PECHS, Karachi" />
        </Field>
        <Field label="Province">
          <Select value={form.mother_province} onChange={(v) => update("mother_province", v as SubmitFormData["mother_province"])}
            options={[
              { value: "PUNJAB",      label: "Punjab" },
              { value: "SINDH",       label: "Sindh" },
              { value: "KPK",         label: "KPK" },
              { value: "BALOCHISTAN", label: "Balochistan" },
              { value: "GB",          label: "Gilgit-Baltistan" },
              { value: "AJK",         label: "AJ&K" },
              { value: "ICT",         label: "Islamabad Capital Territory" },
            ]}
          />
        </Field>
        <Field label="District">
          <Input value={form.mother_district} onChange={(v) => update("mother_district", v)} />
        </Field>
        <Field label="Blood group" hint="optional">
          <Select value={form.mother_blood_group} onChange={(v) => update("mother_blood_group", v)}
            options={[
              { value: "",    label: "—" },
              ...["A+","A-","B+","B-","AB+","AB-","O+","O-"].map((g) => ({ value: g, label: g })),
            ]}
          />
        </Field>
      </div>
    </div>
  );
}

function FatherStep({ form, update }: StepProps) {
  return (
    <div>
      <h2 className="text-lg font-medium">Father's details</h2>
      <p className="mt-1 text-xs text-[var(--color-fg-muted)]">
        Optional — leave the CNIC blank to skip and submit a single-parent registration.
      </p>
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <Field label="CNIC" hint="XXXXX-XXXXXXX-X (or blank to skip)">
          <Input value={form.father_cnic} onChange={(v) => update("father_cnic", v)} placeholder="42101-9876543-2" />
        </Field>
        <Field label="Full name">
          <Input value={form.father_full_name} onChange={(v) => update("father_full_name", v)} placeholder="Ali Siddiqui" />
        </Field>
        <Field label="Date of birth">
          <Input type="date" value={form.father_dob} onChange={(v) => update("father_dob", v)} />
        </Field>
        <Field label="Contact number">
          <Input value={form.father_contact} onChange={(v) => update("father_contact", v)} placeholder="+92-321-1111111" />
        </Field>
      </div>
    </div>
  );
}

function BirthStep({ form, update }: StepProps) {
  return (
    <div>
      <h2 className="text-lg font-medium">Birth details</h2>
      <p className="mt-1 text-xs text-[var(--color-fg-muted)]">
        These fields drive the AI verification rules — anomalies here cause flags.
      </p>
      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <Field label="Attending doctor" full>
          <Input value={form.attending_doctor} onChange={(v) => update("attending_doctor", v)} placeholder="Dr. Ahmed Khan" />
        </Field>
        <Field label="PMDC license" hint="PMDC-XXXXXX">
          <Input value={form.doctor_license_no} onChange={(v) => update("doctor_license_no", v)} placeholder="PMDC-456789" />
        </Field>
        <Field label="Birth date & time">
          <Input type="datetime-local" value={form.birth_datetime} onChange={(v) => update("birth_datetime", v)} />
        </Field>
        <Field label="Delivery type">
          <Select value={form.delivery_type} onChange={(v) => update("delivery_type", v as SubmitFormData["delivery_type"])}
            options={[
              { value: "NORMAL",    label: "Normal vaginal" },
              { value: "C_SECTION", label: "C-section" },
              { value: "ASSISTED",  label: "Assisted (forceps/vacuum)" },
              { value: "OTHER",     label: "Other" },
            ]}
          />
        </Field>
        <Field label="Birth weight (kg)" hint="0.30 – 7.00">
          <Input type="number" step="0.01" value={form.birth_weight_kg} onChange={(v) => update("birth_weight_kg", v)} />
        </Field>
        <Field label="Outcome">
          <Select value={form.birth_outcome} onChange={(v) => update("birth_outcome", v as SubmitFormData["birth_outcome"])}
            options={[
              { value: "LIVE_BIRTH",            label: "Live birth" },
              { value: "STILLBORN",             label: "Stillborn" },
              { value: "DECEASED_AFTER_BIRTH",  label: "Deceased after birth" },
            ]}
          />
        </Field>
        <Field label="Child's gender">
          <Select value={form.child_gender} onChange={(v) => update("child_gender", v as SubmitFormData["child_gender"])}
            options={[
              { value: "MALE",   label: "Male" },
              { value: "FEMALE", label: "Female" },
              { value: "OTHER",  label: "Other" },
            ]}
          />
        </Field>
        <Field label="Child's name" hint="optional">
          <Input value={form.child_full_name} onChange={(v) => update("child_full_name", v)} placeholder="Ahmad Siddiqui" />
        </Field>
        <Field label="Remarks" full hint="optional">
          <Input value={form.remarks} onChange={(v) => update("remarks", v)} placeholder="Anything the AI engine should know" />
        </Field>
      </div>
    </div>
  );
}

function ReviewStep({ form }: { form: SubmitFormData }) {
  return (
    <div>
      <h2 className="text-lg font-medium">Review and submit</h2>
      <p className="mt-1 text-xs text-[var(--color-fg-muted)]">
        Once submitted the AI engine processes the record immediately. You'll
        see it land in <code className="font-mono">PENDING</code> on the
        submissions page.
      </p>

      <div className="mt-6 grid gap-px overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-border)] md:grid-cols-2">
        <ReviewCard title="Mother">
          <Row label="CNIC"    value={form.mother_cnic} mono />
          <Row label="Name"    value={form.mother_full_name} />
          <Row label="DOB"     value={form.mother_dob} mono />
          <Row label="Contact" value={form.mother_contact} mono />
          <Row label="Address" value={form.mother_address} />
          <Row label="Region"  value={`${form.mother_district}, ${form.mother_province}`} />
        </ReviewCard>
        <ReviewCard title="Father">
          {form.father_cnic ? (
            <>
              <Row label="CNIC"    value={form.father_cnic} mono />
              <Row label="Name"    value={form.father_full_name} />
              <Row label="DOB"     value={form.father_dob} mono />
              <Row label="Contact" value={form.father_contact} mono />
            </>
          ) : (
            <div className="text-xs text-[var(--color-fg-subtle)]">
              No father provided — single-parent registration.
            </div>
          )}
        </ReviewCard>
        <ReviewCard title="Birth">
          <Row label="Doctor"   value={`${form.attending_doctor} (${form.doctor_license_no})`} />
          <Row label="When"     value={form.birth_datetime} mono />
          <Row label="Delivery" value={form.delivery_type} />
          <Row label="Weight"   value={`${form.birth_weight_kg} kg`} mono />
          <Row label="Outcome"  value={form.birth_outcome} />
        </ReviewCard>
        <ReviewCard title="Child">
          <Row label="Gender" value={form.child_gender} />
          <Row label="Name"   value={form.child_full_name || "(unnamed)"} />
          {form.remarks && <Row label="Remarks" value={form.remarks} />}
        </ReviewCard>
      </div>
    </div>
  );
}

function ReviewCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-[var(--color-bg-card)] p-5">
      <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {title}
      </div>
      <div className="mt-3 space-y-1.5">{children}</div>
    </div>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-4 text-xs">
      <span className="text-[var(--color-fg-subtle)]">{label}</span>
      <span
        className={
          "text-right text-[var(--color-fg)] " + (mono ? "font-mono" : "")
        }
      >
        {value || "—"}
      </span>
    </div>
  );
}

function Field({
  label,
  hint,
  full,
  children,
}: {
  label: string;
  hint?: string;
  full?: boolean;
  children: React.ReactNode;
}) {
  return (
    <label className={"block " + (full ? "md:col-span-2" : "")}>
      <span className="flex items-center justify-between font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {label}
        {hint && <span className="normal-case tracking-normal text-[var(--color-fg-subtle)]">{hint}</span>}
      </span>
      <div className="mt-1.5">{children}</div>
    </label>
  );
}

function Input({
  value,
  onChange,
  ...rest
}: Omit<React.InputHTMLAttributes<HTMLInputElement>, "onChange" | "value"> & {
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <input
      {...rest}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm text-[var(--color-fg)] outline-none transition focus:border-[var(--color-accent)]"
    />
  );
}

function Select({
  value,
  onChange,
  options,
}: {
  value: string;
  onChange: (v: string) => void;
  options: { value: string; label: string }[];
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="w-full rounded-lg border border-[var(--color-border)] bg-[var(--color-bg)] px-3 py-2 text-sm text-[var(--color-fg)] outline-none transition focus:border-[var(--color-accent)]"
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}
