-- 20290000000098_mumbai_migration_schema_and_extensions.sql
-- Final schema parity and extensions migration for Mumbai deployment

-- 1. Enable pg_trgm for fuzzy search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 2. Ensure categories table
CREATE TABLE IF NOT EXISTS public.categories (
    id SERIAL PRIMARY KEY,
    name TEXT,
    image_url TEXT
);
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.categories TO anon, authenticated, service_role;

-- 3. Ensure admin_activity_log table
CREATE TABLE IF NOT EXISTS public.admin_activity_log (
    id BIGSERIAL PRIMARY KEY,
    admin_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    action TEXT,
    target_type TEXT,
    target_id TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.admin_activity_log ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.admin_activity_log TO anon, authenticated, service_role;

-- 4. Admin Users missing columns
ALTER TABLE public.admin_users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.admin_users ADD COLUMN IF NOT EXISTS admin_level TEXT;
ALTER TABLE public.admin_users ADD COLUMN IF NOT EXISTS permissions JSONB;
ALTER TABLE public.admin_users ADD COLUMN IF NOT EXISTS created_by UUID;
ALTER TABLE public.admin_users ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.admin_users ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- 5. Withdrawals check constraint update
ALTER TABLE public.withdrawals DROP CONSTRAINT IF EXISTS withdrawals_user_role_check;
ALTER TABLE public.withdrawals ADD CONSTRAINT withdrawals_user_role_check CHECK (user_role IN ('seller', 'rider', 'delivery_partner'));

-- 6. Add support_tickets to realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.support_tickets;
