import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import { createAccountApp } from "./app.js";

const PORT = Number(process.env.ACCOUNT_PORT ?? env.PORT ?? 3009);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createAccountApp(rt);
  app.listen(PORT, () => {
    console.log(`[account-service] listening on :${PORT} (store=${rt.storeBackend})`);
  });
}

main().catch((err) => {
  console.error("[account-service] failed to start:", err);
  process.exit(1);
});
