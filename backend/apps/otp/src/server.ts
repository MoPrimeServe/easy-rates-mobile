import { env } from "@easyrates/config";
import { createAuthCoreRuntime } from "@easyrates/auth-core";
import { createOtpApp } from "./app.js";

const PORT = Number(process.env.OTP_PORT ?? env.PORT ?? 3002);

async function main(): Promise<void> {
  const rt = await createAuthCoreRuntime();
  const app = createOtpApp(rt);
  app.listen(PORT, () => {
    console.log(
      `[otp-service] listening on :${PORT} (store=${rt.storeBackend}, mock=${env.OTP_MOCK})`,
    );
  });
}

main().catch((err) => {
  console.error("[otp-service] failed to start:", err);
  process.exit(1);
});
