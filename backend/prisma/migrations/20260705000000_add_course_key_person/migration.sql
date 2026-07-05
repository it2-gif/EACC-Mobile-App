ALTER TABLE "courses"
ADD COLUMN IF NOT EXISTS "key_person_lms_user_id" VARCHAR(100),
ADD COLUMN IF NOT EXISTS "key_person_name" VARCHAR(200);

CREATE INDEX IF NOT EXISTS "courses_key_person_lms_user_id_idx"
ON "courses"("key_person_lms_user_id");
