import { env } from "@easyrates/config";
import { createGatewayApp } from "./app.js";
import { ROUTES } from "./routes.js";

const PORT = Number(process.env.GATEWAY_PORT ?? env.GATEWAY_PORT ?? 8080);

function main(): void {
  const app = createGatewayApp();
  app.listen(PORT, () => {
    const table = ROUTES.map(
      (r) => `    /api/v1/${r.segments.join("|")}/* → ${r.target}`,
    ).join("\n");
    console.log(
      `[gateway] listening on :${PORT} — single origin http://localhost:${PORT}/api/v1\n` +
        `[gateway] routing table:\n${table}`,
    );
  });
}

main();
