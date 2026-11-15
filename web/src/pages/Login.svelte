<script lang="ts">
  import { supabase } from "../supabase";

  let email = $state("");
  let password = $state("");
  let error = $state<string | null>(null);
  let busy = $state(false);

  async function onsubmit(e: SubmitEvent) {
    e.preventDefault();
    if (!supabase) {
      error = "The app is not configured: VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are missing.";
      return;
    }
    busy = true;
    error = null;
    const result = await supabase.auth.signInWithPassword({ email, password });
    busy = false;
    if (result.error) error = result.error.message;
    // Redirect after sign-in (Settings or Shortlist) is wired up in milestone 3.
  }
</script>

<main class="login">
  <h1>Job Application Assistant</h1>
  <form {onsubmit}>
    <label>
      Email
      <input type="email" autocomplete="username" required bind:value={email} />
    </label>
    <label>
      Password
      <input type="password" autocomplete="current-password" required bind:value={password} />
    </label>
    {#if error}<p class="error" role="alert">{error}</p>{/if}
    <button type="submit" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
  </form>
</main>
