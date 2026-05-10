"use server";

import { revalidatePath } from "next/cache";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { ProcessResult, BatchResult } from "@/lib/ai/types";

export async function processOneAction(brn: string): Promise<ProcessResult> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("ai_process_record", { p_brn: brn });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/ai-engine");
  return data as ProcessResult;
}

export async function processAllPendingAction(limit: number = 25): Promise<BatchResult | { ok: false; error: string }> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("ai_process_all_pending", { p_limit: limit });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/ai-engine");
  return data as BatchResult;
}
