"use client";

import { createBrowserClient } from "@supabase/ssr";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;

// Cookie-aware browser client. Use in client components.
export const supabaseBrowser = createBrowserClient(url, key, {
  realtime: { params: { eventsPerSecond: 10 } },
});
