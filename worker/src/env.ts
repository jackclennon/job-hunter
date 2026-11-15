export interface Env {
  ASSETS: Fetcher;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  SECRETS_KEY: string;
  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;
  // The owner's API keys, shared by every user.
  ANTHROPIC_API_KEY: string;
  REED_API_KEY: string;
  ADZUNA_APP_ID: string;
  ADZUNA_APP_KEY: string;
}
