-- Full verification after both migrations
SELECT
    name,
    open_time::text,
    close_time::text,
    is_active,
    is_accepting_orders,
    verification_status,
    (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time AS ist_now,
    CASE
        WHEN is_active = false THEN 'false (inactive shop)'::text
        WHEN open_time IS NULL OR close_time IS NULL THEN 'manual (no hours)'::text
        WHEN open_time::time <= close_time::time THEN
            CASE WHEN (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time >= open_time::time
                      AND (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time <= close_time::time
                 THEN 'true (normal shift, in range)'
                 ELSE 'false (normal shift, out of range)' END
        ELSE
            CASE WHEN (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time >= open_time::time
                      OR (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time <= close_time::time
                 THEN 'true (night shift, in range)'
                 ELSE 'false (night shift, out of range)' END
    END AS expected_state
FROM public.shops
ORDER BY name;
