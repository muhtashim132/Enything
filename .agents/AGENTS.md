# Enything Project Rules

## Database Queries
- **Soft Deletes**: The `products` table uses soft deletes (`is_deleted` boolean flag). Whenever querying the `products` table using Supabase (e.g. `supabase.from('products').select()`), you MUST ALWAYS include `.eq('is_deleted', false)` to ensure deleted products are not fetched.
