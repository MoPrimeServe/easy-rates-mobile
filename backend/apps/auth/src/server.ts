import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import { createAuthApp } from "./app.js";

const PORT = Number(process.env.AUTH_PORT ?? env.PORT ?? 3001);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createAuthApp(rt);
  app.listen(PORT, () => {
    console.log(
      `[auth-service] listening on :${PORT} (store=${rt.storeBackend}, otp=${env.OTP_SERVICE_URL})`,
    );
  });
}

main().catch((err) => {
  console.error("[auth-service] failed to start:", err);
  process.exit(1);
});
