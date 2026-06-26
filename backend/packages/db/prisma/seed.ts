/**
 * Minimal seed — proves the schema round-trips real rows through the live DB.
 * Built to canonical: passwordless User (NO passwordHash), idNumberHash is a
 * placeholder HMAC, OtpPurpose is LOGIN/REGISTRATION only, municipalityId on all
 * tenant-scoped tables, Decimal money as strings.
 *
 * Idempotent: upserts on natural keys so re-running does not duplicate rows.
 */
import { config as loadDotenv } from "dotenv";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { PrismaClient, Prisma } from "@prisma/client";

// Load the monorepo-root .env (two levels up from packages/db/prisma) so the
// seed works regardless of cwd.
const here = dirname(fileURLToPath(import.meta.url));
loadDotenv({ path: resolve(here, "../../../.env") });

const prisma = new PrismaClient();

async function main(): Promise<void> {
  // 1. Municipality (DECISION-C seed — Phase 1 single tenant)
  const emfuleni = await prisma.municipality.upsert({
    where: { code: "EMFULENI" },
    update: {},
    create: { name: "Emfuleni Local Municipality", code: "EMFULENI" },
  });

  // 2. User — passwordless (ADR-002). idNumberHash is a placeholder keyed hash.
  const user = await prisma.user.upsert({
    where: { phone: "+27821234567" },
    update: {},
    create: {
      phone: "+27821234567",
      email: "ratepayer@example.co.za",
      displayName: "Test Ratepayer",
      idNumberHash: "seed-hmac-placeholder-not-a-real-id",
      kycStatus: "VERIFIED",
    },
  });

  // 3. Account linked to the user + municipality
  const account = await prisma.account.upsert({
    where: { accountNumber: "ACC001" },
    update: {},
    create: {
      accountNumber: "ACC001",
      userId: user.id,
      municipalityId: emfuleni.id,
      status: "ACTIVE",
    },
  });

  // 4. Property (municipality master data; accountNumber is the soft-ref key)
  await prisma.property.upsert({
    where: { accountNumber: "ACC001" },
    update: {},
    create: {
      municipalityId: emfuleni.id,
      accountNumber: "ACC001",
      address: "123 Main Street, Vanderbijlpark",
      erfNumber: "ERF4567",
      ownerName: "Test Ratepayer",
      holderIdNumberHashes: ["seed-hmac-holder-placeholder"],
      city: "Emfuleni",
    },
  });

  // 5. Bill + line items (idempotent via a stable check on account+period)
  const period = "2025-05";
  let bill = await prisma.bill.findFirst({
    where: { accountNumber: account.accountNumber, period },
  });
  if (!bill) {
    bill = await prisma.bill.create({
      data: {
        municipalityId: emfuleni.id,
        accountNumber: account.accountNumber,
        period,
        totalAmount: new Prisma.Decimal("1450.00"),
        dueDate: new Date("2025-06-15T00:00:00.000Z"),
        status: "CURRENT",
        lineItems: {
          create: [
            {
              description: "Water consumption",
              amount: new Prisma.Decimal("620.00"),
              category: "WATER",
              anomalyFlag: true,
              historicalAverage: new Prisma.Decimal("310.00"),
            },
            {
              description: "Electricity usage",
              amount: new Prisma.Decimal("530.00"),
              category: "ELECTRICITY",
            },
            {
              description: "Property rates",
              amount: new Prisma.Decimal("300.00"),
              category: "PROPERTY_RATES",
            },
          ],
        },
        aiCalculation: {
          create: {
            estimatedAmount: new Prisma.Decimal("1140.00"),
            confidence: 0.82,
            reasoning:
              "Water line item appears high versus 6-month average consumption.",
            modelVersion: "seed-v0",
          },
        },
      },
    });
  }

  // 6. Objection on the flagged water line item (UNDER_REVIEW)
  const waterLine = await prisma.billLineItem.findFirst({
    where: { billId: bill.id, category: "WATER" },
  });
  if (waterLine) {
    const existing = await prisma.objection.findFirst({
      where: { userId: user.id, lineItemId: waterLine.id },
    });
    if (!existing) {
      await prisma.objection.create({
        data: {
          userId: user.id,
          municipalityId: emfuleni.id,
          lineItemId: waterLine.id,
          category: "WRONG_METER_READING",
          status: "UNDER_REVIEW",
          refNumber: "ELM-2026-000001",
          notes: "Meter reading does not match my actual usage.",
          submittedAt: new Date(),
        },
      });
    }
  }

  // 7. A notification + an audit event (proves those tables write)
  await prisma.notification.create({
    data: {
      userId: user.id,
      type: "OBJECTION_RECEIVED",
      channel: "EMAIL",
      status: "SENT",
    },
  });
  await prisma.auditEvent.create({
    data: {
      userId: user.id,
      event: "OBJECTION_SUBMITTED",
      entityType: "Objection",
      entityId: "ELM-2026-000001",
      metadata: { ip: "127.0.0.1", source: "seed" },
    },
  });

  const counts = {
    municipality: await prisma.municipality.count(),
    user: await prisma.user.count(),
    account: await prisma.account.count(),
    property: await prisma.property.count(),
    bill: await prisma.bill.count(),
    billLineItem: await prisma.billLineItem.count(),
    aiAmountCalculation: await prisma.aIAmountCalculation.count(),
    objection: await prisma.objection.count(),
    notification: await prisma.notification.count(),
    auditEvent: await prisma.auditEvent.count(),
  };
  console.log("[seed] done:", JSON.stringify(counts, null, 2));
}

main()
  .then(async () => {
    await prisma.$disconnect();
  })
  .catch(async (e) => {
    console.error("[seed] failed:", e);
    await prisma.$disconnect();
    process.exit(1);
  });
