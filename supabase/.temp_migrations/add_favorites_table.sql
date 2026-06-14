CREATE TABLE IF NOT EXISTS public.customer_favorites (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
    shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    -- Ensure either product_id or shop_id is provided, but not both
    CONSTRAINT favorite_target_check CHECK (
        (product_id IS NOT NULL AND shop_id IS NULL) OR
        (product_id IS NULL AND shop_id IS NOT NULL)
    ),
    -- Ensure a customer can't favorite the exact same thing twice
    CONSTRAINT unique_customer_product UNIQUE (customer_id, product_id),
    CONSTRAINT unique_customer_shop UNIQUE (customer_id, shop_id)
);

-- Enable RLS
ALTER TABLE public.customer_favorites ENABLE ROW LEVEL SECURITY;

-- Policy: Customers can read their own favorites
CREATE POLICY "Customers can view own favorites"
    ON public.customer_favorites FOR SELECT
    TO authenticated
    USING (auth.uid() = customer_id);

-- Policy: Customers can insert their own favorites
CREATE POLICY "Customers can insert own favorites"
    ON public.customer_favorites FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = customer_id);

-- Policy: Customers can delete their own favorites
CREATE POLICY "Customers can delete own favorites"
    ON public.customer_favorites FOR DELETE
    TO authenticated
    USING (auth.uid() = customer_id);

-- Refresh schema cache
NOTIFY pgrst, 'reload schema';
