import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import { createBillApp } from "./app.js";

const PORT = Number(process.env.BILL_PORT ?? env.PORT ?? 3005);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createBillApp(rt);
  app.listen(PORT, () => {
    console.log(`[bill-service] listening on :${PORT} (store=${rt.storeBackend})`);
  });
}

main().catch((err) => {
  console.error("[bill-service] failed to start:", err);
  process.exit(1);
});
