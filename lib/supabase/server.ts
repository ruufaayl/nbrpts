import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

/**
 * Cookie-aware Supabase client for use in RSCs, route handlers, and server
 * actions. The cookies() proxy is async in Next 15+, so this helper is async.
 *
 * Usage:
 *   const supabase = await getSupabaseServer();
 *   const { data } = await supabase.rpc("get_pipeline_summary");
 */
export async function getSupabaseServer() {
  const cookieStore = await cookies();
  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options)
          );
        } catch {
          // Server Components cannot mutate cookies; that's fine —
          // the middleware/server-action paths will refresh the session.
        }
      },
    },
  });
}
