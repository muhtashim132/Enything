#!/bin/bash

# Ensure the script stops on the first error
set -e

echo "🚀 Starting Supabase deployment..."

echo "📦 Pushing database migrations..."
supabase db push
echo "✅ Database migrations pushed successfully."

echo "⚡ Deploying Edge Functions..."
# This command deploys all functions in the supabase/functions directory
supabase functions deploy
echo "✅ Edge functions deployed successfully."

echo "🎉 Deployment complete!"
