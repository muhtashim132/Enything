# Enything Project Rules

## User Profile
- **User / Lead Developer**: Muhtashim Kamran Nazki

## Database Queries
- **Soft Deletes**: The `products` table uses soft deletes (`is_deleted` boolean flag). Whenever querying the `products` table using Supabase (e.g. `supabase.from('products').select()`), you MUST ALWAYS include `.eq('is_deleted', false)` to ensure deleted products are not fetched.

## Testing Discipline & Zero Test Leftovers
- **Immediate Test Cleanup**: Whenever running tests, integration test scripts, or creating mock records, you MUST ALWAYS immediately delete/purge any test products, test orders, and test shops once testing finishes. Never leave test entities in the live database.
