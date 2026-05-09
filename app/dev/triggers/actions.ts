"use server";

import { revalidatePath } from "next/cache";
import { supabaseServer } from "@/lib/supabase/server";

const DEMO_NAMES = [
  "Ahmad", "Hassan", "Hussain", "Fatima", "Mariam", "Zara", "Bilal",
  "Sana", "Rabia", "Khadija", "Imran", "Sara", "Ayesha", "Mehreen",
];

function randomName() {
  return DEMO_NAMES[Math.floor(Math.random() * DEMO_NAMES.length)] +
    " " +
    DEMO_NAMES[Math.floor(Math.random() * DEMO_NAMES.length)];
}

export async function submitDemoRecordAction() {
  const { data: hospital } = await supabaseServer
    .from("hospital")
    .select("hospital_id")
    .eq("hrn", "HRN-2019-0001")
    .single();

  const { data: mother } = await supabaseServer
    .from("parent_guardian")
    .select("guardian_id")
    .eq("gender", "FEMALE")
    .eq("nationality", "Pakistani")
    .limit(1)
    .single();

  if (!hospital || !mother) {
    return { ok: false as const, error: "Could not find demo hospital or mother." };
  }

  const { data, error } = await supabaseServer.rpc("submit_birth_record", {
    p_hospital_id: hospital.hospital_id,
    p_mother_id: mother.guardian_id,
    p_father_id: null,
    p_attending_doctor: "Dr. Demo Doctor",
    p_doctor_license_no: "PMDC-100200",
    p_birth_datetime: new Date(Date.now() - 1000 * 60 * 30).toISOString(),
    p_delivery_type: "NORMAL",
    p_birth_weight_kg: 3.2,
    p_birth_outcome: "LIVE_BIRTH",
    p_child_gender: Math.random() < 0.5 ? "MALE" : "FEMALE",
    p_child_full_name: randomName(),
    p_remarks: "Submitted from /dev/triggers lab",
  });

  if (error) return { ok: false as const, error: error.message };
  revalidatePath("/dev/triggers");
  return { ok: true as const, message: `Submitted ${data?.brn ?? "new record"} (PENDING)` };
}

export async function verifyAction(birthRecordId: string, officerId: string) {
  const { data, error } = await supabaseServer.rpc("verify_birth_record", {
    p_birth_record_id: birthRecordId,
    p_officer_id: officerId,
    p_remarks: "Verified from /dev/triggers lab",
  });
  if (error) return { ok: false as const, error: error.message };
  revalidatePath("/dev/triggers");
  return {
    ok: true as const,
    message: `Verified ${data?.brn}. Cascade: child + B-Form + SMS created.`,
  };
}

export async function authorizeAction(bformId: string, officerId: string) {
  const { data, error } = await supabaseServer.rpc("authorize_bform", {
    p_bform_id: bformId,
    p_officer_id: officerId,
  });
  if (error) return { ok: false as const, error: error.message };
  revalidatePath("/dev/triggers");
  return {
    ok: true as const,
    message: `Authorized ${data?.bform_number}. SMS flipped to SENT.`,
  };
}

export async function reissueAction(
  childId: string,
  officerId: string,
  reason: string
) {
  const { data, error } = await supabaseServer.rpc("reissue_bform", {
    p_child_id: childId,
    p_officer_id: officerId,
    p_reason: reason,
  });
  if (error) return { ok: false as const, error: error.message };
  revalidatePath("/dev/triggers");
  return {
    ok: true as const,
    message: `Reissued as ${data?.bform_number} (v${data?.version}).`,
  };
}
