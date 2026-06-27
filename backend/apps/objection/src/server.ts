import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import {
  startNotificationWorker,
  startObjectionSubmitWorker,
} from "@easyrates/queue";
import { createObjectionApp } from "./app.js";

const PORT = Number(process.env.OBJECTION_PORT ?? env.PORT ?? 3005);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createObjectionApp(rt);

  // Run the submission worker (and the notification worker it feeds) in-process
  // for local dev so submit → refNumber → notification completes end-to-end.
  const submitWorker = startObjectionSubmitWorker();
  const notifyWorker = startNotificationWorker();
  if (!submitWorker) {
    console.warn(
      "[objection-service] objection-submit worker not running (Redis down) — submits will not finalise.",
    );
  }

  app.listen(PORT, () => {
    console.log(`[objection-service] listening on :${PORT} (store=${rt.storeBackend})`);
  });

  const shutdown = async (): Promise<void> => {
    await submitWorker?.close();
    await notifyWorker?.close();
    process.exit(0);
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}

main().catch((err) => {
  console.error("[objection-service] failed to start:", err);
  process.exit(1);
});
