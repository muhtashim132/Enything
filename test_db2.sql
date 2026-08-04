SELECT proname, prosrc 
FROM pg_proc 
WHERE prosrc ILIKE '%payment_deadline%';
