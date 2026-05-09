import "server-only";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

// Anonymous server-side client. Use this for RSC reads/writes that don't
// need elevated privileges. Phase 4 will add a cookie-aware variant.
export const supabaseServer = createClient(url, key, {
  auth: { persistSession: false },
});
