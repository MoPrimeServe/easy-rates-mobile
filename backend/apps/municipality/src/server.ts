import { env } from "@easyrates/config";
import { startNotificationWorker } from "@easyrates/queue";
import { createMunicipalityApp } from "./app.js";

const PORT = Number(process.env.MUNICIPALITY_PORT ?? env.PORT ?? 3007);

async function main(): Promise<void> {
  const app = createMunicipalityApp();

  // Run the notification worker in-process so the enqueued status-change
  // notification is dispatched (marked SENT) for local dev.
  const worker = startNotificationWorker();

  app.listen(PORT, () => {
    console.log(`[municipality-service] listening on :${PORT}`);
  });

  const shutdown = async (): Promise<void> => {
    await worker?.close();
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("[municipality-service] failed to start:", err);
  process.exit(1);
});
