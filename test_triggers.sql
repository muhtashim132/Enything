SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.orders'::regclass;
