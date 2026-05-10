"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getSupabaseServer } from "@/lib/supabase/server";

export type ActionResult = { ok: boolean; error?: string; brn?: string };

export async function verifyRecordAction(
  brn: string,
  remarks: string | null,
): Promise<ActionResult> {
  const supabase = await getSupabaseServer();
  const { error } = await supabase.rpc("verify_birth_record_v2", {
    p_brn: brn,
    p_remarks: remarks?.trim() || null,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/officer");
  revalidatePath("/officer/queue");
  revalidatePath(`/officer/record/${encodeURIComponent(brn)}`);
  return { ok: true, brn };
}

export async function rejectRecordAction(
  brn: string,
  remarks: string,
): Promise<ActionResult> {
  if (!remarks?.trim()) return { ok: false, error: "Rejection requires a reason" };
  const supabase = await getSupabaseServer();
  const { error } = await supabase.rpc("reject_birth_record_v2", {
    p_brn: brn,
    p_remarks: remarks.trim(),
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/officer");
  revalidatePath("/officer/queue");
  revalidatePath(`/officer/record/${encodeURIComponent(brn)}`);
  return { ok: true, brn };
}

export async function flagRecordAction(
  brn: string,
  remarks: string,
): Promise<ActionResult> {
  const supabase = await getSupabaseServer();
  const { error } = await supabase.rpc("flag_birth_record_v2", {
    p_brn: brn,
    p_remarks: remarks?.trim() || "Manually flagged for review",
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/officer");
  revalidatePath("/officer/queue");
  revalidatePath(`/officer/record/${encodeURIComponent(brn)}`);
  return { ok: true, brn };
}

export async function authorizeBformAction(
  bformId: string,
): Promise<ActionResult> {
  const supabase = await getSupabaseServer();
  const { error } = await supabase.rpc("authorize_bform_v2", {
    p_bform_id: bformId,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/officer");
  revalidatePath("/officer/bforms");
  return { ok: true };
}

export async function reissueBformAction(
  childId: string,
  reason: string,
): Promise<ActionResult> {
  if (!reason?.trim()) return { ok: false, error: "Reissue reason is required" };
  const supabase = await getSupabaseServer();
  const { error } = await supabase.rpc("reissue_bform_v2", {
    p_child_id: childId,
    p_reason: reason.trim(),
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/officer/bforms");
  return { ok: true };
}

export async function searchRedirectAction(formData: FormData) {
  const q = String(formData.get("q") ?? "").trim();
  if (q.length < 2) return;
  redirect(`/officer/search?q=${encodeURIComponent(q)}`);
}
