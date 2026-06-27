import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import { startNotificationWorker } from "@easyrates/queue";
import { createNotificationApp } from "./app.js";

const PORT = Number(process.env.NOTIFICATION_PORT ?? env.PORT ?? 3006);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createNotificationApp(rt);

  // Run the notification dispatch worker in-process for local dev so enqueued
  // rows are marked SENT (the persisted row is the source of truth).
  const worker = startNotificationWorker();

  app.listen(PORT, () => {
    console.log(`[notification-service] listening on :${PORT} (store=${rt.storeBackend})`);
  });

  const shutdown = async (): Promise<void> => {
    await worker?.close();
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("[notification-service] failed to start:", err);
  process.exit(1);
});
