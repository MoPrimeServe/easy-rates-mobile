/**
 * Minimal seed — proves the schema round-trips real rows through the live DB.
 * Built to canonical: passwordless User (NO passwordHash), idNumberHash is a
 * placeholder HMAC, OtpPurpose is LOGIN/REGISTRATION only, municipalityId on all
 * tenant-scoped tables, Decimal money as strings.
 *
 * Idempotent: upserts on natural keys so re-running does not duplicate rows.
 */
import { createHmac } from "node:crypto";
import { config as loadDotenv } from "dotenv";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { PrismaClient, Prisma } from "@prisma/client";

// Load the monorepo-root .env (two levels up from packages/db/prisma) so the
// seed works regardless of cwd.
const here = dirname(fileURLToPath(import.meta.url));
loadDotenv({ path: resolve(here, "../../../.env") });

const prisma = new PrismaClient();

// ADR-003 keyed HMAC — the SAME function the services use (auth-core hashIdNumber).
// The pepper comes from .env (ID_NUMBER_HMAC_PEPPER); a fallback keeps the seed
// runnable if the var is absent, but the live .env supplies it.
const PEPPER =
  process.env.ID_NUMBER_HMAC_PEPPER ??
  "dev-only-id-hmac-pepper-change-me-2222222222222222222222";
const hashId = (idNumber: string): string =>
  createHmac("sha256", PEPPER).update(idNumber).digest("hex");

// Deterministic plaintext SA IDs for the seed holder (never stored — only the
// hash is persisted). These drive the identity gate so the seed user matches
// their seed properties.
const SEED_ID_NUMBER = "8001015009087";

async function main(): Promise<void> {
  // 1. Municipality (DECISION-C seed — Phase 1 single tenant)
  const emfuleni = await prisma.municipality.upsert({
    where: { code: "EMFULENI" },
    update: {},
    create: { name: "Emfuleni Local Municipality", code: "EMFULENI" },
  });

  const idHash = hashId(SEED_ID_NUMBER);

  // 2. User — passwordless (ADR-002). idNumberHash is the keyed HMAC (ADR-003)
  //    so the identity gate (user.idNumberHash ∈ property.holderIdNumberHashes)
  //    actually MATCHES the seed properties. Notification prefs scaffold the
  //    Notification Preferences screen.
  const user = await prisma.user.upsert({
    where: { phone: "+27821234567" },
    update: {
      idNumberHash: idHash,
      smsEnabled: true,
      pushEnabled: true,
      emailEnabled: true,
      preferredLanguage: "en",
    },
    create: {
      phone: "+27821234567",
      email: "ratepayer@example.co.za",
      displayName: "Test Ratepayer",
      idNumberHash: idHash,
      kycStatus: "VERIFIED",
      smsEnabled: true,
      pushEnabled: true,
      emailEnabled: true,
      preferredLanguage: "en",
    },
  });

  // 3. Accounts linked to the user — TWO service accounts so account-service
  //    lists multiple linked properties and the dashboard can consolidate.
  const account = await prisma.account.upsert({
    where: { accountNumber: "10045821" },
    update: { userId: user.id },
    create: {
      accountNumber: "10045821",
      userId: user.id,
      municipalityId: emfuleni.id,
      status: "ACTIVE",
    },
  });
  await prisma.account.upsert({
    where: { accountNumber: "10045822" },
    update: { userId: user.id },
    create: {
      accountNumber: "10045822",
      userId: user.id,
      municipalityId: emfuleni.id,
      status: "ACTIVE",
    },
  });

  // 4. Properties (municipality master data; accountNumber is the soft-ref key).
  //    holderIdNumberHashes carries the user's keyed hash → identity gate hits.
  //    ward / extentSqm / municipalValue / dataAsOf live in metadata (the synced
  //    raw fields the property-detail route surfaces).
  await prisma.property.upsert({
    where: { accountNumber: "10045821" },
    update: {
      holderIdNumberHashes: [idHash],
      metadata: {
        ward: "Ward 12",
        extentSqm: 495,
        municipalValue: "1850000.00",
        dataAsOf: "2026-06-15T02:00:00.000Z",
      },
    },
    create: {
      municipalityId: emfuleni.id,
      accountNumber: "10045821",
      address: "123 Main Street, Vereeniging",
      erfNumber: "ERF/001/VRG",
      ownerName: "Test Ratepayer",
      holderIdNumberHashes: [idHash],
      city: "Emfuleni",
      metadata: {
        ward: "Ward 12",
        extentSqm: 495,
        municipalValue: "1850000.00",
        dataAsOf: "2026-06-15T02:00:00.000Z",
      },
    },
  });
  await prisma.property.upsert({
    where: { accountNumber: "10045822" },
    update: {
      holderIdNumberHashes: [idHash],
      metadata: {
        ward: "Ward 21",
        extentSqm: 612,
        municipalValue: "2100000.00",
        dataAsOf: "2026-06-15T02:00:00.000Z",
      },
    },
    create: {
      municipalityId: emfuleni.id,
      accountNumber: "10045822",
      address: "8 Frikkie Meyer Blvd, Vanderbijlpark",
      erfNumber: "ERF/002/VBP",
      ownerName: "Test Ratepayer",
      holderIdNumberHashes: [idHash],
      city: "Emfuleni",
      metadata: {
        ward: "Ward 21",
        extentSqm: 612,
        municipalValue: "2100000.00",
        dataAsOf: "2026-06-15T02:00:00.000Z",
      },
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
            confidence: 0.82, // below 0.85 → ai-estimate returns null estimate
            reasoning:
              "Water line item appears high versus 6-month average consumption.",
            modelVersion: "seed-v0",
          },
        },
      },
    });
  }

  // 5b. A SECOND bill on the second account with a CONFIDENT AI calc
  //     (confidence ≥ 0.85) so the ai-estimate confident branch is exercisable.
  const period2 = "2026-06";
  let bill2 = await prisma.bill.findFirst({
    where: { accountNumber: "10045822", period: period2 },
  });
  if (!bill2) {
    bill2 = await prisma.bill.create({
      data: {
        municipalityId: emfuleni.id,
        accountNumber: "10045822",
        period: period2,
        totalAmount: new Prisma.Decimal("612.40"),
        dueDate: new Date("2026-07-15T00:00:00.000Z"),
        status: "OVERDUE",
        lineItems: {
          create: [
            {
              description: "Water consumption (45 kl)",
              amount: new Prisma.Decimal("498.40"),
              category: "WATER",
              anomalyFlag: true,
              historicalAverage: new Prisma.Decimal("310.00"),
            },
            {
              description: "Sanitation levy",
              amount: new Prisma.Decimal("34.20"),
              category: "SANITATION",
            },
          ],
        },
        aiCalculation: {
          create: {
            estimatedAmount: new Prisma.Decimal("430.00"),
            confidence: 0.91, // at/above 0.85 → estimate + variance shown
            reasoning:
              "Your meter reading appears high relative to your 6-month average consumption.",
            modelVersion: "seed-v0",
          },
        },
      },
    });
  }

  // 5c. Fixture reset for the harness — clear any objections the e2e / Postman
  //     runs created on THIS seed user (everything except the canonical
  //     ELM-2026-000001), plus their child rows, so the smoke tests stay
  //     re-runnable: each run disputes a fresh line item, and a submitted
  //     objection permanently blocks re-disputing its charge. Scoped to the
  //     seed user's non-canonical objections only — never touches other data.
  const staleObjections = await prisma.objection.findMany({
    where: { userId: user.id, refNumber: { not: "ELM-2026-000001" } },
    select: { id: true },
  });
  if (staleObjections.length > 0) {
    const ids = staleObjections.map((o) => o.id);
    await prisma.municipalityResponse.deleteMany({
      where: { objectionId: { in: ids } },
    });
    await prisma.evidenceFile.deleteMany({ where: { objectionId: { in: ids } } });
    await prisma.notification.deleteMany({ where: { objectionId: { in: ids } } });
    await prisma.objection.deleteMany({ where: { id: { in: ids } } });
    await prisma.objectionDraft.deleteMany({ where: { userId: user.id } });
    console.log(
      `[seed] fixture reset: removed ${ids.length} harness objection(s) for the seed user.`,
    );
  }

  // 6. Objection on the flagged water line item (UNDER_REVIEW)
  const waterLine = await prisma.billLineItem.findFirst({
    where: { billId: bill.id, category: "WATER" },
  });
  if (waterLine) {
    // Idempotent on refNumber (unique) so re-seeding after a schema change,
    // which can re-create the water line item, never duplicates the ref.
    const existing = await prisma.objection.findFirst({
      where: { refNumber: "ELM-2026-000001" },
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
