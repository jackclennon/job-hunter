import { Hono } from "hono";
import type { Env } from "./env";
import { serviceClient } from "./db";

const app = new Hono<{ Bindings: Env }>().basePath("/api");

// Milestone 1: proves the Worker can reach Supabase by reading one row.
app.get("/health", async (c) => {
  const { data, error } = await serviceClient(c.env).rpc("health").single();
  if (error) {
    return c.json({ ok: false, error: "database unreachable" }, 503);
  }
  return c.json({ ok: true, database: data });
});

app.notFound((c) => c.json({ error: "not found" }, 404));
app.onError((err, c) => {
  console.error("unhandled error", err instanceof Error ? err.message : "unknown");
  return c.json({ error: "internal error" }, 500);
});

export default {
  fetch: app.fetch,
  // Cron Triggers. The daily enqueue and the runner arrive in milestones 2 and 6.
  async scheduled(controller: ScheduledController, _env: Env, _ctx: ExecutionContext) {
    console.log("scheduled", controller.cron);
  },
} satisfies ExportedHandler<Env>;
