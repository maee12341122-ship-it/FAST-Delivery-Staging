CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role TEXT NOT NULL CHECK (role IN ('customer', 'admin', 'courier')),
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  username TEXT UNIQUE,
  password_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (role = 'customer' OR username IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS users_role_active_idx ON users(role, is_active);

CREATE TABLE IF NOT EXISTS restaurants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  image_url TEXT NOT NULL DEFAULT '',
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  opening_hour SMALLINT NOT NULL DEFAULT 11 CHECK (opening_hour BETWEEN 0 AND 23),
  closing_hour SMALLINT NOT NULL DEFAULT 22 CHECK (closing_hour BETWEEN 1 AND 24),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((latitude IS NULL AND longitude IS NULL) OR
         (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180))
);

CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE RESTRICT,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'other',
  price_yer BIGINT NOT NULL CHECK (price_yer >= 0),
  unit TEXT NOT NULL DEFAULT 'حبة',
  image_url TEXT NOT NULL DEFAULT '',
  is_available BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS products_restaurant_active_idx ON products(restaurant_id, is_available);

CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
  customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE RESTRICT,
  courier_id UUID REFERENCES users(id) ON DELETE RESTRICT,
  customer_name TEXT NOT NULL,
  customer_phone TEXT NOT NULL,
  address_text TEXT NOT NULL,
  customer_latitude DOUBLE PRECISION,
  customer_longitude DOUBLE PRECISION,
  delivery_distance_km NUMERIC(8,2),
  notes TEXT NOT NULL DEFAULT '',
  subtotal_yer BIGINT NOT NULL CHECK (subtotal_yer >= 0),
  delivery_fee_yer BIGINT NOT NULL CHECK (delivery_fee_yer >= 0),
  total_yer BIGINT NOT NULL CHECK (total_yer >= 0),
  payment_method TEXT NOT NULL DEFAULT 'cash_on_delivery' CHECK (payment_method = 'cash_on_delivery'),
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'collected')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'accepted', 'preparing', 'ready', 'assigned',
    'picked_up', 'on_the_way', 'delivered', 'cancelled'
  )),
  cash_collected_by UUID REFERENCES users(id) ON DELETE RESTRICT,
  cash_collected_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((customer_latitude IS NULL AND customer_longitude IS NULL) OR
         (customer_latitude BETWEEN -90 AND 90 AND customer_longitude BETWEEN -180 AND 180)),
  CHECK ((payment_status = 'unpaid' AND cash_collected_by IS NULL AND cash_collected_at IS NULL) OR
         (payment_status = 'collected' AND cash_collected_by IS NOT NULL AND cash_collected_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS orders_customer_created_idx ON orders(customer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_courier_status_idx ON orders(courier_id, status);
CREATE INDEX IF NOT EXISTS orders_status_created_idx ON orders(status, created_at DESC);

CREATE TABLE IF NOT EXISTS order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id) ON DELETE SET NULL,
  product_name TEXT NOT NULL,
  unit TEXT NOT NULL,
  quantity INTEGER NOT NULL CHECK (quantity BETWEEN 1 AND 99),
  unit_price_yer BIGINT NOT NULL CHECK (unit_price_yer >= 0),
  line_total_yer BIGINT NOT NULL CHECK (line_total_yer >= 0)
);
CREATE INDEX IF NOT EXISTS order_items_order_idx ON order_items(order_id);

CREATE TABLE IF NOT EXISTS courier_locations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  courier_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS courier_locations_order_time_idx ON courier_locations(order_id, recorded_at DESC);

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app_settings(key, value)
VALUES ('business', '{"currency":"YER","payment_method":"cash_on_delivery"}'::jsonb)
ON CONFLICT (key) DO NOTHING;
