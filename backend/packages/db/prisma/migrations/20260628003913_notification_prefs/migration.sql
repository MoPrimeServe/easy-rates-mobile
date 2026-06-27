-- notification_prefs: captures the account-service notification-preference
-- fields on User (smsEnabled / pushEnabled / emailEnabled / preferredLanguage)
-- that were previously applied to the live DB via `prisma db push` without a
-- migration. Generated with `prisma migrate diff` so migration history == schema.
-- The live easyrates_dev already had these columns (db push), so this migration
-- was recorded as applied via `prisma migrate resolve --applied` rather than
-- re-executed. A fresh database applies it normally.

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "emailEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "preferredLanguage" TEXT NOT NULL DEFAULT 'en',
ADD COLUMN     "pushEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "smsEnabled" BOOLEAN NOT NULL DEFAULT true;
