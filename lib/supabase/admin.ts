import "server-only";
import { createClient } from "@supabase/supabase-js";

// Service-role client. NEVER import this from client code.
// `server-only` causes a build error if any client component imports this file.
const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

export const supabaseAdmin = key
  ? createClient(url, key, { auth: { persistSession: false } })
  : null;
