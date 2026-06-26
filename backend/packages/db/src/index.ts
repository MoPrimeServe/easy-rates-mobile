import { PrismaClient } from "@prisma/client";

/**
 * Singleton PrismaClient.
 *
 * Every service imports `{ prisma }` from `@easyrates/db` — no service may
 * instantiate its own client (avoids exhausting the connection pool; see nfr.md
 * connection_limit math). In dev, the instance is cached on `globalThis` so HMR
 * / repeated module loads do not spawn new pools.
 */
const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const prisma: PrismaClient =
  globalForPrisma.prisma ??
  new PrismaClient({
    log:
      process.env.NODE_ENV === "development"
        ? ["warn", "error"]
        : ["error"],
  });

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}

export * from "@prisma/client";
export { PrismaClient };
