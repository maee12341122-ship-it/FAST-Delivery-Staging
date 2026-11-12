-- FAST Delivery: compatibility addition for the schema supplied with this project.
-- The Flutter app stores the OneSignal subscription ID on a customer row.
-- Run this statement in Supabase SQL Editor only if the column is not already present.
ALTER TABLE public.customers
ADD COLUMN IF NOT EXISTS onesignal_player_id text;
