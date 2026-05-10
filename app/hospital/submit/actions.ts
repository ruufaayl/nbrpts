"use server";

import { revalidatePath } from "next/cache";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { SubmitFormData } from "@/lib/hospital/types";

export async function submitBirthRecordAction(form: SubmitFormData) {
  const supabase = await getSupabaseServer();

  const { data, error } = await supabase.rpc("submit_birth_record_v2", {
    p_mother_cnic:        form.mother_cnic.trim() || null,
    p_mother_full_name:   form.mother_full_name.trim(),
    p_mother_dob:         form.mother_dob,
    p_mother_contact:     form.mother_contact.trim(),
    p_mother_address:     form.mother_address.trim(),
    p_mother_province:    form.mother_province,
    p_mother_district:    form.mother_district.trim(),
    p_mother_blood_group: form.mother_blood_group || null,
    p_father_cnic:        form.father_cnic.trim() || null,
    p_father_full_name:   form.father_full_name.trim() || null,
    p_father_dob:         form.father_dob || null,
    p_father_contact:     form.father_contact.trim() || null,
    p_attending_doctor:   form.attending_doctor.trim(),
    p_doctor_license_no:  form.doctor_license_no.trim(),
    p_birth_datetime:     form.birth_datetime,
    p_delivery_type:      form.delivery_type,
    p_birth_weight_kg:    Number(form.birth_weight_kg),
    p_birth_outcome:      form.birth_outcome,
    p_child_gender:       form.child_gender,
    p_child_full_name:    form.child_full_name.trim() || null,
    p_remarks:            form.remarks.trim() || null,
  });

  if (error) {
    return { ok: false as const, error: error.message };
  }

  revalidatePath("/hospital");
  revalidatePath("/hospital/submissions");
  return {
    ok: true as const,
    brn: (data as { brn: string } | null)?.brn ?? null,
  };
}
