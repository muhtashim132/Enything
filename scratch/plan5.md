# PostgrestException Error Analysis
The user got a `PostgrestException` when rejecting the order: `column "v_platform_gst_rate" does not exist`.
Looking at Migration 30, I accidentally left a line of PL/pgSQL code that referenced `v_platform_gst_rate`. I had realized I didn't need it and wrote a second assignment to `v_new_grand` immediately below it, but PL/pgSQL executes sequentially, so it crashed on the first line.

# Plan
Create Migration 31 to cleanly remove the erroneous `v_new_grand` assignment line that references `v_platform_gst_rate` from `reallocate_cancelled_delivery_fees`.
