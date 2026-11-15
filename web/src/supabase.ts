import { createClient } from "@supabase/supabase-js";

// The browser uses Supabase only to sign in and keep the session.
// All data goes through the Worker's /api routes.
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const supabase = url && anonKey ? createClient(url, anonKey) : null;
