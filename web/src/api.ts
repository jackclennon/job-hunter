import { supabase } from "./supabase";

/** fetch wrapper that adds the signed-in user's access token. */
export async function api(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  const session = supabase ? (await supabase.auth.getSession()).data.session : null;
  if (session) headers.set("Authorization", `Bearer ${session.access_token}`);
  return fetch(`/api${path}`, { ...init, headers });
}
