


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."create_activity_log"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_business_id UUID;
BEGIN

  -- =========================================
  -- BUSINESS ID
  -- =========================================

  v_business_id := COALESCE(
    NEW.business_id,
    OLD.business_id
  );

  -- =========================================
  -- INSERT LOG
  -- =========================================

  INSERT INTO activity_logs (
    id,
    business_id,
    user_id,
    action,
    affected_table,
    record_id,
    metadata,
    created_at
  )
  VALUES (
    gen_random_uuid(),
    v_business_id,
    auth.uid(),
    
    TG_OP,

    TG_TABLE_NAME,

    COALESCE(
      NEW.id,
      OLD.id
    ),

    jsonb_build_object(
      'old_data', to_jsonb(OLD),
      'new_data', to_jsonb(NEW)
    ),

    NOW()
  );

  RETURN COALESCE(NEW, OLD);

END;
$$;


ALTER FUNCTION "public"."create_activity_log"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrease_stock"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

DECLARE
  v_business_id uuid;
  v_previous_stock integer;
  v_new_stock integer;

BEGIN

  -- Obtener business_id de la venta
  SELECT business_id
  INTO v_business_id
  FROM sales
  WHERE id = NEW.sale_id;

  -- Obtener stock actual
  SELECT stock_quantity
  INTO v_previous_stock
  FROM products
  WHERE id = NEW.product_id
  AND business_id = v_business_id;

  -- Nuevo stock
  v_new_stock := v_previous_stock - NEW.quantity;

  -- Actualizar stock
  UPDATE products
  SET stock_quantity = v_new_stock
  WHERE id = NEW.product_id
  AND business_id = v_business_id;

  -- Registrar movimiento
  INSERT INTO inventory_movements (
    id,
    business_id,
    product_id,
    movement_type,
    quantity_change,
    previous_stock,
    new_stock,
    reference_id,
    reference_type,
    notes
  )
  VALUES (
    gen_random_uuid(),
    v_business_id,
    NEW.product_id,
    'sale',
    -NEW.quantity,
    v_previous_stock,
    v_new_stock,
    NEW.sale_id,
    'sale',
    'Venta realizada'
  );

  RETURN NEW;

END;

$$;


ALTER FUNCTION "public"."decrease_stock"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    business_id,
    full_name,
    role,
    status,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NULL,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.email,
      'Usuario'
    ),
    'owner',
    'active',
    NOW(),
    NOW()
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    RAISE LOG 'Error creating profile for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increase_stock_from_purchase"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$

DECLARE
  v_business_id uuid;
  v_previous_stock integer;
  v_new_stock integer;

BEGIN

  -- Obtener business_id de la compra
  SELECT business_id
  INTO v_business_id
  FROM purchases
  WHERE id = NEW.purchase_id;

  -- Obtener stock actual
  SELECT stock_quantity
  INTO v_previous_stock
  FROM products
  WHERE id = NEW.product_id
  AND business_id = v_business_id;

  -- Nuevo stock
  v_new_stock := v_previous_stock + NEW.quantity;

  -- Actualizar stock
  UPDATE products
  SET stock_quantity = v_new_stock
  WHERE id = NEW.product_id
  AND business_id = v_business_id;

  -- Registrar movimiento
  INSERT INTO inventory_movements (
    id,
    business_id,
    product_id,
    movement_type,
    quantity_change,
    previous_stock,
    new_stock,
    reference_id,
    reference_type,
    notes
  )
  VALUES (
    gen_random_uuid(),
    v_business_id,
    NEW.product_id,
    'purchase',
    NEW.quantity,
    v_previous_stock,
    v_new_stock,
    NEW.purchase_id,
    'purchase',
    'Compra registrada'
  );

  RETURN NEW;

END;

$$;


ALTER FUNCTION "public"."increase_stock_from_purchase"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."activity_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "affected_table" character varying(100),
    "record_id" "uuid",
    "ip_address" character varying(50),
    "created_at" timestamp without time zone DEFAULT "now"(),
    "metadata" "jsonb"
);


ALTER TABLE "public"."activity_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."businesses" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" character varying(255) NOT NULL,
    "business_type" character varying(100),
    "owner_name" character varying(255),
    "phone" character varying(30),
    "email" character varying(255),
    "address" "text",
    "subscription_plan" character varying(50) DEFAULT 'free'::character varying,
    "status" character varying(20) DEFAULT 'active'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone
);


ALTER TABLE "public"."businesses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "name" character varying(255) NOT NULL,
    "description" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone
);


ALTER TABLE "public"."categories" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "full_name" character varying(255) NOT NULL,
    "phone" character varying(30),
    "email" character varying(255),
    "address" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."devices" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "device_type" character varying(100),
    "serial_number" character varying(255),
    "mode" character varying(50),
    "delivery_date" "date",
    "status" character varying(20) DEFAULT 'active'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone,
    CONSTRAINT "devices_mode_check" CHECK ((("mode")::"text" = ANY ((ARRAY['sale'::character varying, 'rental'::character varying])::"text"[])))
);


ALTER TABLE "public"."devices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_movements" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "product_id" "uuid",
    "movement_type" character varying,
    "quantity_change" integer NOT NULL,
    "previous_stock" integer,
    "new_stock" integer,
    "reference_id" "uuid",
    "reference_type" character varying,
    "notes" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    CONSTRAINT "inventory_movements_movement_type_check" CHECK ((("movement_type")::"text" = ANY ((ARRAY['sale'::character varying, 'purchase'::character varying, 'manual_adjustment'::character varying, 'loss'::character varying, 'return'::character varying])::"text"[])))
);


ALTER TABLE "public"."inventory_movements" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."legacy_users" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "full_name" character varying(255) NOT NULL,
    "email" character varying(255) NOT NULL,
    "password_hash" "text" NOT NULL,
    "role" character varying(50) NOT NULL,
    "status" character varying(20) DEFAULT 'active'::character varying,
    "last_login" timestamp without time zone,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone,
    CONSTRAINT "users_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['superadmin'::character varying, 'owner'::character varying, 'admin'::character varying, 'cashier'::character varying, 'warehouse'::character varying, 'technician'::character varying])::"text"[])))
);


ALTER TABLE "public"."legacy_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."master_products_catalog" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "barcode" character varying NOT NULL,
    "product_name" character varying NOT NULL,
    "brand" character varying,
    "category" character varying,
    "unit" character varying DEFAULT 'unidad'::character varying,
    "description" "text",
    "image_url" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."master_products_catalog" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "category_id" "uuid",
    "supplier_id" "uuid",
    "barcode" character varying(100),
    "name" character varying(255) NOT NULL,
    "description" "text",
    "purchase_price" numeric(12,2) DEFAULT 0,
    "sale_price" numeric(12,2) NOT NULL,
    "stock_quantity" integer DEFAULT 0,
    "minimum_stock" integer DEFAULT 0,
    "unit" character varying(50) DEFAULT 'unidad'::character varying,
    "status" character varying(20) DEFAULT 'active'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone,
    "master_product_id" "uuid",
    "simple_category" character varying,
    CONSTRAINT "chk_products_purchase_price_non_negative" CHECK (("purchase_price" >= (0)::numeric)),
    CONSTRAINT "chk_products_sale_price_non_negative" CHECK (("sale_price" >= (0)::numeric)),
    CONSTRAINT "chk_products_stock_non_negative" CHECK (("stock_quantity" >= 0))
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "business_id" "uuid",
    "full_name" character varying(255),
    "role" character varying(50),
    "status" character varying(20) DEFAULT 'active'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    CONSTRAINT "chk_profiles_role" CHECK ((("role")::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying, 'inventory'::character varying, 'viewer'::character varying])::"text"[]))),
    CONSTRAINT "profiles_role_check" CHECK ((("role")::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying, 'warehouse'::character varying, 'technician'::character varying])::"text"[])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchase_items" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "purchase_id" "uuid",
    "product_id" "uuid",
    "quantity" integer NOT NULL,
    "unit_cost" numeric(12,2) NOT NULL,
    "subtotal" numeric(12,2) NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"(),
    CONSTRAINT "chk_purchase_items_quantity_positive" CHECK (("quantity" > 0)),
    CONSTRAINT "chk_purchase_items_unit_cost_positive" CHECK (("unit_cost" >= (0)::numeric))
);


ALTER TABLE "public"."purchase_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."purchases" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "supplier_id" "uuid",
    "user_id" "uuid",
    "total" numeric(12,2) NOT NULL,
    "status" character varying(20) DEFAULT 'completed'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone,
    "invoice_photo_url" "text",
    "processing_status" character varying DEFAULT 'pending'::character varying,
    "supplier_name" character varying,
    CONSTRAINT "chk_purchases_total_positive" CHECK (("total" >= (0)::numeric))
);


ALTER TABLE "public"."purchases" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sale_items" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "sale_id" "uuid",
    "product_id" "uuid",
    "quantity" integer NOT NULL,
    "unit_price" numeric(12,2) NOT NULL,
    "subtotal" numeric(12,2) NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"(),
    CONSTRAINT "chk_sale_items_quantity_positive" CHECK (("quantity" > 0)),
    CONSTRAINT "chk_sale_items_unit_price_positive" CHECK (("unit_price" >= (0)::numeric))
);


ALTER TABLE "public"."sale_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "user_id" "uuid",
    "customer_id" "uuid",
    "total" numeric(12,2) NOT NULL,
    "payment_method" character varying(50),
    "status" character varying(20) DEFAULT 'completed'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone,
    CONSTRAINT "chk_sales_total_positive" CHECK (("total" >= (0)::numeric))
);


ALTER TABLE "public"."sales" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "plan_name" character varying(50) NOT NULL,
    "price" numeric(12,2) DEFAULT 0,
    "start_date" "date" NOT NULL,
    "end_date" "date",
    "status" character varying(20) DEFAULT 'active'::character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."suppliers" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "name" character varying(255) NOT NULL,
    "contact_name" character varying(255),
    "phone" character varying(30),
    "email" character varying(255),
    "address" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "deleted_at" timestamp without time zone
);


ALTER TABLE "public"."suppliers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sync_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_id" "uuid",
    "device_id" character varying,
    "sync_type" character varying,
    "records_uploaded" integer DEFAULT 0,
    "records_downloaded" integer DEFAULT 0,
    "sync_status" character varying DEFAULT 'success'::character varying,
    "error_message" "text",
    "created_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."sync_logs" OWNER TO "postgres";


ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."businesses"
    ADD CONSTRAINT "businesses_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."businesses"
    ADD CONSTRAINT "businesses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_serial_number_key" UNIQUE ("serial_number");



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."master_products_catalog"
    ADD CONSTRAINT "master_products_catalog_barcode_key" UNIQUE ("barcode");



ALTER TABLE ONLY "public"."master_products_catalog"
    ADD CONSTRAINT "master_products_catalog_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchase_items"
    ADD CONSTRAINT "purchase_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."purchases"
    ADD CONSTRAINT "purchases_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sync_logs"
    ADD CONSTRAINT "sync_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "unique_product_per_business" UNIQUE ("barcode", "business_id");



ALTER TABLE ONLY "public"."legacy_users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."legacy_users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_customers_business_id" ON "public"."customers" USING "btree" ("business_id");



CREATE INDEX "idx_inventory_business_id" ON "public"."inventory_movements" USING "btree" ("business_id");



CREATE INDEX "idx_inventory_created_at" ON "public"."inventory_movements" USING "btree" ("created_at");



CREATE INDEX "idx_inventory_product_id" ON "public"."inventory_movements" USING "btree" ("product_id");



CREATE INDEX "idx_logs_business_id" ON "public"."activity_logs" USING "btree" ("business_id");



CREATE INDEX "idx_master_products_barcode" ON "public"."master_products_catalog" USING "btree" ("barcode");



CREATE INDEX "idx_products_barcode" ON "public"."products" USING "btree" ("barcode");



CREATE INDEX "idx_products_business_barcode" ON "public"."products" USING "btree" ("business_id", "barcode");



CREATE INDEX "idx_products_business_id" ON "public"."products" USING "btree" ("business_id");



CREATE INDEX "idx_products_deleted_at" ON "public"."products" USING "btree" ("deleted_at");



CREATE INDEX "idx_profiles_business_id" ON "public"."profiles" USING "btree" ("business_id");



CREATE INDEX "idx_purchase_items_product_id" ON "public"."purchase_items" USING "btree" ("product_id");



CREATE INDEX "idx_purchase_items_purchase_id" ON "public"."purchase_items" USING "btree" ("purchase_id");



CREATE INDEX "idx_purchases_business_id" ON "public"."purchases" USING "btree" ("business_id");



CREATE INDEX "idx_purchases_created_at" ON "public"."purchases" USING "btree" ("created_at");



CREATE INDEX "idx_purchases_deleted_at" ON "public"."purchases" USING "btree" ("deleted_at");



CREATE INDEX "idx_sale_items_product_id" ON "public"."sale_items" USING "btree" ("product_id");



CREATE INDEX "idx_sale_items_sale_id" ON "public"."sale_items" USING "btree" ("sale_id");



CREATE INDEX "idx_sales_business_id" ON "public"."sales" USING "btree" ("business_id");



CREATE INDEX "idx_sales_created_at" ON "public"."sales" USING "btree" ("created_at");



CREATE INDEX "idx_sales_deleted_at" ON "public"."sales" USING "btree" ("deleted_at");



CREATE INDEX "idx_suppliers_business_id" ON "public"."suppliers" USING "btree" ("business_id");



CREATE INDEX "idx_users_business_id" ON "public"."legacy_users" USING "btree" ("business_id");



CREATE OR REPLACE TRIGGER "trg_activity_customers" AFTER INSERT OR UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."create_activity_log"();



CREATE OR REPLACE TRIGGER "trg_activity_products" AFTER INSERT OR UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."create_activity_log"();



CREATE OR REPLACE TRIGGER "trg_activity_purchases" AFTER INSERT OR UPDATE ON "public"."purchases" FOR EACH ROW EXECUTE FUNCTION "public"."create_activity_log"();



CREATE OR REPLACE TRIGGER "trg_activity_sales" AFTER INSERT OR UPDATE ON "public"."sales" FOR EACH ROW EXECUTE FUNCTION "public"."create_activity_log"();



CREATE OR REPLACE TRIGGER "trg_activity_suppliers" AFTER INSERT OR UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."create_activity_log"();



CREATE OR REPLACE TRIGGER "trg_businesses_updated_at" BEFORE UPDATE ON "public"."businesses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_categories_updated_at" BEFORE UPDATE ON "public"."categories" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_customers_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_decrease_stock" AFTER INSERT ON "public"."sale_items" FOR EACH ROW EXECUTE FUNCTION "public"."decrease_stock"();



CREATE OR REPLACE TRIGGER "trg_devices_updated_at" BEFORE UPDATE ON "public"."devices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_products_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_purchases_updated_at" BEFORE UPDATE ON "public"."purchases" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_sales_updated_at" BEFORE UPDATE ON "public"."sales" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_subscriptions_updated_at" BEFORE UPDATE ON "public"."subscriptions" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_suppliers_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trg_users_updated_at" BEFORE UPDATE ON "public"."legacy_users" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trigger_increase_stock_from_purchase" AFTER INSERT ON "public"."purchase_items" FOR EACH ROW EXECUTE FUNCTION "public"."increase_stock_from_purchase"();



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."activity_logs"
    ADD CONSTRAINT "activity_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."devices"
    ADD CONSTRAINT "devices_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_movements"
    ADD CONSTRAINT "inventory_movements_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_master_product_id_fkey" FOREIGN KEY ("master_product_id") REFERENCES "public"."master_products_catalog"("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchase_items"
    ADD CONSTRAINT "purchase_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."purchase_items"
    ADD CONSTRAINT "purchase_items_purchase_id_fkey" FOREIGN KEY ("purchase_id") REFERENCES "public"."purchases"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchases"
    ADD CONSTRAINT "purchases_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."purchases"
    ADD CONSTRAINT "purchases_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."purchases"
    ADD CONSTRAINT "purchases_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sale_items"
    ADD CONSTRAINT "sale_items_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "public"."sales"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sync_logs"
    ADD CONSTRAINT "sync_logs_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."legacy_users"
    ADD CONSTRAINT "users_business_id_fkey" FOREIGN KEY ("business_id") REFERENCES "public"."businesses"("id") ON DELETE CASCADE;



ALTER TABLE "public"."activity_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "activity_logs_insert_by_business" ON "public"."activity_logs" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "activity_logs_select_by_business" ON "public"."activity_logs" FOR SELECT TO "authenticated" USING (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "authenticated_users_can_create_business" ON "public"."businesses" FOR INSERT TO "authenticated" WITH CHECK (true);



ALTER TABLE "public"."businesses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "businesses_select_by_owner" ON "public"."businesses" FOR SELECT TO "authenticated" USING (("id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "businesses_update_by_owner" ON "public"."businesses" FOR UPDATE TO "authenticated" USING (("id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))) WITH CHECK (("id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "categories_insert_by_business" ON "public"."categories" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "categories_no_delete" ON "public"."categories" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "categories_select_by_business" ON "public"."categories" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "categories_update_by_business" ON "public"."categories" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[]))));



ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "customers_insert_by_business" ON "public"."customers" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "customers_no_delete" ON "public"."customers" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "customers_select_by_business" ON "public"."customers" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "customers_update_by_business" ON "public"."customers" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying])::"text"[]))));



ALTER TABLE "public"."devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "devices_insert_by_business" ON "public"."devices" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "devices_select_by_business" ON "public"."devices" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "devices_update_by_business" ON "public"."devices" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying])::"text"[]))));



ALTER TABLE "public"."inventory_movements" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inventory_movements_insert_by_business" ON "public"."inventory_movements" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "inventory_movements_select_by_business" ON "public"."inventory_movements" FOR SELECT TO "authenticated" USING (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



ALTER TABLE "public"."legacy_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."master_products_catalog" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "master_products_catalog_select" ON "public"."master_products_catalog" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_insert_by_business" ON "public"."products" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "products_no_delete" ON "public"."products" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "products_select_by_business" ON "public"."products" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "products_update_by_business" ON "public"."products" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[]))));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."purchase_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "purchase_items_insert_by_business" ON "public"."purchase_items" FOR INSERT TO "authenticated" WITH CHECK (("purchase_id" IN ( SELECT "purchases"."id"
   FROM "public"."purchases"
  WHERE ("purchases"."business_id" = ( SELECT "profiles"."business_id"
           FROM "public"."profiles"
          WHERE ("profiles"."id" = "auth"."uid"()))))));



CREATE POLICY "purchase_items_select_by_business" ON "public"."purchase_items" FOR SELECT TO "authenticated" USING (("purchase_id" IN ( SELECT "purchases"."id"
   FROM "public"."purchases"
  WHERE ("purchases"."business_id" = ( SELECT "profiles"."business_id"
           FROM "public"."profiles"
          WHERE ("profiles"."id" = "auth"."uid"()))))));



ALTER TABLE "public"."purchases" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "purchases_insert_by_business" ON "public"."purchases" FOR INSERT TO "authenticated" WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[]))));



CREATE POLICY "purchases_no_delete" ON "public"."purchases" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "purchases_select_by_business" ON "public"."purchases" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "purchases_update_by_business" ON "public"."purchases" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[]))));



ALTER TABLE "public"."sale_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sale_items_insert_by_business" ON "public"."sale_items" FOR INSERT TO "authenticated" WITH CHECK (("sale_id" IN ( SELECT "sales"."id"
   FROM "public"."sales"
  WHERE ("sales"."business_id" = ( SELECT "profiles"."business_id"
           FROM "public"."profiles"
          WHERE ("profiles"."id" = "auth"."uid"()))))));



CREATE POLICY "sale_items_select_by_business" ON "public"."sale_items" FOR SELECT TO "authenticated" USING (("sale_id" IN ( SELECT "sales"."id"
   FROM "public"."sales"
  WHERE ("sales"."business_id" = ( SELECT "profiles"."business_id"
           FROM "public"."profiles"
          WHERE ("profiles"."id" = "auth"."uid"()))))));



ALTER TABLE "public"."sales" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sales_insert_by_business" ON "public"."sales" FOR INSERT TO "authenticated" WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying])::"text"[]))));



CREATE POLICY "sales_no_delete" ON "public"."sales" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "sales_select_by_business" ON "public"."sales" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "sales_update_by_business" ON "public"."sales" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'cashier'::character varying])::"text"[]))));



ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "subscriptions_insert_by_business" ON "public"."subscriptions" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "subscriptions_select_by_business" ON "public"."subscriptions" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "subscriptions_update_by_business" ON "public"."subscriptions" FOR UPDATE TO "authenticated" USING (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))) WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "suppliers_insert_by_business" ON "public"."suppliers" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "suppliers_no_delete" ON "public"."suppliers" FOR DELETE TO "authenticated" USING (false);



CREATE POLICY "suppliers_select_by_business" ON "public"."suppliers" FOR SELECT TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ("deleted_at" IS NULL)));



CREATE POLICY "suppliers_update_by_business" ON "public"."suppliers" FOR UPDATE TO "authenticated" USING ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[])))) WITH CHECK ((("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))) AND ((( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())))::"text" = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'inventory'::character varying])::"text"[]))));



ALTER TABLE "public"."sync_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sync_logs_insert_by_business" ON "public"."sync_logs" FOR INSERT TO "authenticated" WITH CHECK (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "sync_logs_select_by_business" ON "public"."sync_logs" FOR SELECT TO "authenticated" USING (("business_id" = ( SELECT "profiles"."business_id"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"()))));



CREATE POLICY "users_can_update_own_profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "users_can_view_own_profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."create_activity_log"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_activity_log"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_activity_log"() TO "service_role";



GRANT ALL ON FUNCTION "public"."decrease_stock"() TO "anon";
GRANT ALL ON FUNCTION "public"."decrease_stock"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrease_stock"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increase_stock_from_purchase"() TO "anon";
GRANT ALL ON FUNCTION "public"."increase_stock_from_purchase"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."increase_stock_from_purchase"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";


















GRANT ALL ON TABLE "public"."activity_logs" TO "anon";
GRANT ALL ON TABLE "public"."activity_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."activity_logs" TO "service_role";



GRANT ALL ON TABLE "public"."businesses" TO "anon";
GRANT ALL ON TABLE "public"."businesses" TO "authenticated";
GRANT ALL ON TABLE "public"."businesses" TO "service_role";



GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."devices" TO "anon";
GRANT ALL ON TABLE "public"."devices" TO "authenticated";
GRANT ALL ON TABLE "public"."devices" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_movements" TO "anon";
GRANT ALL ON TABLE "public"."inventory_movements" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_movements" TO "service_role";



GRANT ALL ON TABLE "public"."legacy_users" TO "anon";
GRANT ALL ON TABLE "public"."legacy_users" TO "authenticated";
GRANT ALL ON TABLE "public"."legacy_users" TO "service_role";



GRANT ALL ON TABLE "public"."master_products_catalog" TO "anon";
GRANT ALL ON TABLE "public"."master_products_catalog" TO "authenticated";
GRANT ALL ON TABLE "public"."master_products_catalog" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."purchase_items" TO "anon";
GRANT ALL ON TABLE "public"."purchase_items" TO "authenticated";
GRANT ALL ON TABLE "public"."purchase_items" TO "service_role";



GRANT ALL ON TABLE "public"."purchases" TO "anon";
GRANT ALL ON TABLE "public"."purchases" TO "authenticated";
GRANT ALL ON TABLE "public"."purchases" TO "service_role";



GRANT ALL ON TABLE "public"."sale_items" TO "anon";
GRANT ALL ON TABLE "public"."sale_items" TO "authenticated";
GRANT ALL ON TABLE "public"."sale_items" TO "service_role";



GRANT ALL ON TABLE "public"."sales" TO "anon";
GRANT ALL ON TABLE "public"."sales" TO "authenticated";
GRANT ALL ON TABLE "public"."sales" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."suppliers" TO "anon";
GRANT ALL ON TABLE "public"."suppliers" TO "authenticated";
GRANT ALL ON TABLE "public"."suppliers" TO "service_role";



GRANT ALL ON TABLE "public"."sync_logs" TO "anon";
GRANT ALL ON TABLE "public"."sync_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."sync_logs" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";



































