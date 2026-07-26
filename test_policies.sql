SELECT polname FROM pg_policy WHERE polrelid = 'public.orders'::regclass;
