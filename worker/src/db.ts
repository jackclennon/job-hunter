import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Env } from "./env";

/**
 * Service-role Supabase client. It bypasses Row Level Security, so user routes
 * must never use it directly: they use the per-user helper added in milestone 3,
 * which returns query builders already filtered on the verified user id.
 */
export function serviceClient(env: Env): SupabaseClient {
  return createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}
