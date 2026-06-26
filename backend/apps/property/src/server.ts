import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import { createPropertyApp } from "./app.js";

const PORT = Number(process.env.PROPERTY_PORT ?? env.PORT ?? 3003);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createPropertyApp(rt);
  app.listen(PORT, () => {
    console.log(`[property-service] listening on :${PORT} (store=${rt.storeBackend})`);
  });
}

main().catch((err) => {
  console.error("[property-service] failed to start:", err);
  process.exit(1);
});
