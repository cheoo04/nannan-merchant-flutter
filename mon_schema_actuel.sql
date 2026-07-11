


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


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."app_role" AS ENUM (
    'client',
    'merchant',
    'delivery',
    'admin',
    'support'
);


ALTER TYPE "public"."app_role" OWNER TO "postgres";


CREATE TYPE "public"."merchant_status" AS ENUM (
    'pending',
    'active',
    'suspended'
);


ALTER TYPE "public"."merchant_status" OWNER TO "postgres";


CREATE TYPE "public"."notification_type" AS ENUM (
    'order',
    'system',
    'payment',
    'delivery'
);


ALTER TYPE "public"."notification_type" OWNER TO "postgres";


CREATE TYPE "public"."order_status" AS ENUM (
    'pending',
    'accepted',
    'in_delivery',
    'delivered',
    'cancelled',
    'refunded'
);


ALTER TYPE "public"."order_status" OWNER TO "postgres";


CREATE TYPE "public"."partner_app_status" AS ENUM (
    'pending',
    'approved',
    'rejected'
);


ALTER TYPE "public"."partner_app_status" OWNER TO "postgres";


CREATE TYPE "public"."partner_app_type" AS ENUM (
    'merchant',
    'courier'
);


ALTER TYPE "public"."partner_app_type" OWNER TO "postgres";


CREATE TYPE "public"."payment_method" AS ENUM (
    'cash',
    'mobile_money',
    'card'
);


ALTER TYPE "public"."payment_method" OWNER TO "postgres";


CREATE TYPE "public"."payment_status" AS ENUM (
    'pending',
    'paid',
    'failed',
    'refunded'
);


ALTER TYPE "public"."payment_status" OWNER TO "postgres";


CREATE TYPE "public"."prescription_status" AS ENUM (
    'received',
    'analyzing',
    'quoted',
    'accepted',
    'paid',
    'cancelled'
);


ALTER TYPE "public"."prescription_status" OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."partner_applications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "public"."partner_app_type" NOT NULL,
    "status" "public"."partner_app_status" DEFAULT 'pending'::"public"."partner_app_status" NOT NULL,
    "payload" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "admin_note" "text",
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."partner_applications" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_partner_application"("_app_id" "uuid") RETURNS "public"."partner_applications"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE app public.partner_applications; new_role public.app_role;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  SELECT * INTO app FROM public.partner_applications WHERE id = _app_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found'; END IF;
  IF app.status <> 'pending' THEN RAISE EXCEPTION 'already_reviewed'; END IF;
  new_role := CASE WHEN app.type = 'merchant' THEN 'merchant'::public.app_role ELSE 'delivery'::public.app_role END;
  UPDATE public.users_profiles SET role = new_role WHERE id = app.user_id;
  IF app.type = 'merchant' THEN
    INSERT INTO public.merchants (owner_id,name,category,description,address,phone,city_code,status)
    VALUES (app.user_id,COALESCE(app.payload->>'business_name','Mon commerce'),
      COALESCE(app.payload->>'category','autre'),app.payload->>'description',
      app.payload->>'address',app.payload->>'phone',
      COALESCE(app.payload->>'city_code','oume'),'active'::public.merchant_status);
  ELSE
    INSERT INTO public.couriers (user_id,vehicle_type,city_code,is_online)
    VALUES (app.user_id,COALESCE(app.payload->>'vehicle_type','moto'),
      COALESCE(app.payload->>'city_code','oume'),false)
    ON CONFLICT DO NOTHING;
  END IF;
  UPDATE public.partner_applications SET status='approved',reviewed_by=auth.uid(),reviewed_at=now()
    WHERE id=_app_id RETURNING * INTO app;
  RETURN app;
END $$;


ALTER FUNCTION "public"."approve_partner_application"("_app_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_merchant_open_on_order"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.scheduled_at IS NULL AND NOT public.merchant_is_open_now(NEW.merchant_id) THEN
    RAISE EXCEPTION 'merchant_unavailable' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION "public"."enforce_merchant_open_on_order"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."feed_product_suggestions"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.product_suggestions (category, name, description, suggested_price_xof, image_url, usage_count)
  VALUES (NEW.category, NEW.name, NEW.description, NEW.price_xof, NEW.image_url, 1)
  ON CONFLICT (category, name) DO UPDATE
    SET usage_count = public.product_suggestions.usage_count + 1, updated_at = now();
  RETURN NEW;
END $$;


ALTER FUNCTION "public"."feed_product_suggestions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gen_code4"() RETURNS "text"
    LANGUAGE "sql"
    SET "search_path" TO 'public'
    AS $$
  SELECT lpad((floor(random()*10000))::int::text, 4, '0')
$$;


ALTER FUNCTION "public"."gen_code4"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_role public.app_role;
BEGIN
  IF NEW.email = 'tresorbohoui.sb@gmail.com' THEN
    v_role := 'admin';
  ELSE
    v_role := 'client';
  END IF;
  INSERT INTO public.users_profiles (id, email, name, phone, role)
  VALUES (
    NEW.id, NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', NEW.email),
    COALESCE(NEW.raw_user_meta_data->>'phone', NEW.phone),
    v_role
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        role = CASE WHEN EXCLUDED.email = 'tresorbohoui.sb@gmail.com'
                    THEN 'admin'::public.app_role
                    ELSE public.users_profiles.role END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"("_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM public.users_profiles WHERE id = _user_id AND role = 'admin')
$$;


ALTER FUNCTION "public"."is_admin"("_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merchant_is_open_now"("_merchant_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE m public.merchants%ROWTYPE; t time;
BEGIN
  SELECT * INTO m FROM public.merchants WHERE id = _merchant_id;
  IF NOT FOUND THEN RETURN false; END IF;
  IF m.status <> 'active' THEN RETURN false; END IF;
  IF m.is_open = false THEN RETURN false; END IF;
  IF m.pause_until IS NOT NULL AND m.pause_until > now() THEN RETURN false; END IF;
  IF m.auto_schedule_enabled AND m.opening_time IS NOT NULL AND m.closing_time IS NOT NULL THEN
    t := (now() AT TIME ZONE 'UTC')::time;
    IF m.opening_time <= m.closing_time THEN
      IF t < m.opening_time OR t > m.closing_time THEN RETURN false; END IF;
    ELSE
      IF t < m.opening_time AND t > m.closing_time THEN RETURN false; END IF;
    END IF;
  END IF;
  RETURN true;
END $$;


ALTER FUNCTION "public"."merchant_is_open_now"("_merchant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_order_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_owner uuid;
BEGIN
  SELECT owner_id INTO v_owner FROM public.merchants WHERE id = NEW.merchant_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.notifications (user_id, type, title, body, order_id) VALUES
      (NEW.client_id,'order','Commande créée','Votre commande est en attente de confirmation.',NEW.id),
      (v_owner,'order','Nouvelle commande','Une commande vous est adressée. Code: '||NEW.accept_code,NEW.id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'accepted' THEN
      INSERT INTO public.notifications (user_id,type,title,body,order_id) VALUES
        (NEW.client_id,'order','Commande acceptée','Le marchand a accepté votre commande.',NEW.id);
    ELSIF NEW.status = 'in_delivery' THEN
      INSERT INTO public.notifications (user_id,type,title,body,order_id) VALUES
        (NEW.client_id,'delivery','En livraison','Code de livraison: '||NEW.delivery_code,NEW.id),
        (v_owner,'delivery','Commande retirée','Le livreur a récupéré la commande.',NEW.id);
    ELSIF NEW.status = 'delivered' THEN
      INSERT INTO public.notifications (user_id,type,title,body,order_id) VALUES
        (NEW.client_id,'order','Commande livrée','Merci pour votre commande !',NEW.id),
        (v_owner,'order','Commande livrée','Livraison confirmée par le client.',NEW.id);
      IF NEW.courier_id IS NOT NULL THEN
        INSERT INTO public.notifications (user_id,type,title,body,order_id) VALUES
          (NEW.courier_id,'payment','Paiement débloqué','La livraison est validée.',NEW.id);
      END IF;
    ELSIF NEW.status = 'cancelled' THEN
      INSERT INTO public.notifications (user_id,type,title,body,order_id) VALUES
        (NEW.client_id,'order','Commande annulée',NULL,NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION "public"."notify_order_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_partner_application_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE admin_row record; type_label text;
BEGIN
  type_label := CASE WHEN NEW.type = 'merchant' THEN 'marchand' ELSE 'livreur' END;
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.notifications (user_id,type,title,body) VALUES
      (NEW.user_id,'system','Demande envoyée','Votre demande pour devenir '||type_label||' est en cours d''examen.');
    FOR admin_row IN SELECT id FROM public.users_profiles WHERE role = 'admin' LOOP
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (admin_row.id,'system','Nouvelle demande partenaire','Une candidature '||type_label||' attend votre validation.');
    END LOOP;
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'approved' THEN
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (NEW.user_id,'system','Demande acceptée','Bienvenue ! Votre compte '||type_label||' est maintenant actif.');
    ELSIF NEW.status = 'rejected' THEN
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (NEW.user_id,'system','Demande refusée',COALESCE(NEW.admin_note,'Votre candidature '||type_label||' n''a pas été retenue.'));
    END IF;
  END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION "public"."notify_partner_application_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_prescription_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_owner uuid;
BEGIN
  SELECT owner_id INTO v_owner FROM public.merchants WHERE id = NEW.merchant_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.notifications (user_id,type,title,body) VALUES
      (NEW.client_id,'order','Ordonnance envoyée','En attente de validation par la pharmacie.'),
      (v_owner,'order','Nouvelle ordonnance','Un client vous a envoyé une ordonnance.');
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'quoted' THEN
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (NEW.client_id,'order','Devis pharmacie disponible','Le pharmacien a calculé le prix de votre ordonnance.');
    ELSIF NEW.status = 'accepted' THEN
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (v_owner,'order','Devis accepté','Le client a accepté votre devis.');
    ELSIF NEW.status = 'paid' THEN
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (v_owner,'payment','Paiement reçu','Préparez l''ordonnance, un livreur va passer.');
    ELSIF NEW.status = 'cancelled' THEN
      INSERT INTO public.notifications (user_id,type,title,body) VALUES
        (NEW.client_id,'order','Ordonnance annulée',NULL);
    END IF;
  END IF;
  RETURN NEW;
END $$;


ALTER FUNCTION "public"."notify_prescription_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_role_column"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF NOT public.is_admin(auth.uid()) THEN
      NEW.role := OLD.role;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."protect_role_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reject_partner_application"("_app_id" "uuid", "_note" "text") RETURNS "public"."partner_applications"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE app public.partner_applications;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  UPDATE public.partner_applications SET status='rejected',admin_note=_note,reviewed_by=auth.uid(),reviewed_at=now()
    WHERE id=_app_id AND status='pending' RETURNING * INTO app;
  IF NOT FOUND THEN RAISE EXCEPTION 'not_found_or_already_reviewed'; END IF;
  RETURN app;
END $$;


ALTER FUNCTION "public"."reject_partner_application"("_app_id" "uuid", "_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;


ALTER FUNCTION "public"."touch_updated_at"() OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cart_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cart_id" "uuid" NOT NULL,
    "product_id" "uuid",
    "product_name" "text" NOT NULL,
    "product_image" "text",
    "unit_price" integer NOT NULL,
    "qty" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cart_items_qty_check" CHECK (("qty" > 0))
);


ALTER TABLE "public"."cart_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."carts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "merchant_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."carts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "delivery_enabled" boolean DEFAULT true NOT NULL,
    "night_start_hour" integer DEFAULT 21 NOT NULL,
    "night_end_hour" integer DEFAULT 6 NOT NULL,
    "long_distance_threshold_km" numeric DEFAULT 5 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."cities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."couriers" (
    "user_id" "uuid" NOT NULL,
    "is_online" boolean DEFAULT false NOT NULL,
    "last_lat" double precision,
    "last_lng" double precision,
    "last_seen_at" timestamp with time zone,
    "vehicle_type" "text" DEFAULT 'moto'::"text" NOT NULL,
    "city_code" "text" DEFAULT 'oume'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."couriers" REPLICA IDENTITY FULL;


ALTER TABLE "public"."couriers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."merchants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "created_by_courier_id" "uuid",
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "description" "text",
    "address" "text",
    "lat" double precision,
    "lng" double precision,
    "phone" "text",
    "image_url" "text",
    "is_open" boolean DEFAULT true NOT NULL,
    "opening_time" time without time zone,
    "closing_time" time without time zone,
    "auto_schedule_enabled" boolean DEFAULT false NOT NULL,
    "pause_until" timestamp with time zone,
    "status" "public"."merchant_status" DEFAULT 'pending'::"public"."merchant_status" NOT NULL,
    "city_code" "text" DEFAULT 'oume'::"text" NOT NULL,
    "story_images" "text"[] DEFAULT '{}'::"text"[],
    "story_video_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."merchants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "type" "public"."notification_type" DEFAULT 'system'::"public"."notification_type" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text",
    "order_id" "uuid",
    "read_at" timestamp with time zone,
    "city_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."notifications" REPLICA IDENTITY FULL;


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "product_id" "text",
    "product_name" "text" NOT NULL,
    "product_image" "text",
    "qty" integer NOT NULL,
    "unit_price" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "order_items_qty_check" CHECK (("qty" > 0)),
    CONSTRAINT "order_items_unit_price_check" CHECK (("unit_price" >= 0))
);

ALTER TABLE ONLY "public"."order_items" REPLICA IDENTITY FULL;


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "merchant_id" "uuid" NOT NULL,
    "courier_id" "uuid",
    "status" "public"."order_status" DEFAULT 'pending'::"public"."order_status" NOT NULL,
    "total_xof" integer NOT NULL,
    "payment_method" "public"."payment_method" DEFAULT 'cash'::"public"."payment_method" NOT NULL,
    "payment_status" "public"."payment_status" DEFAULT 'pending'::"public"."payment_status" NOT NULL,
    "cash_amount_given" integer,
    "paid_at" timestamp with time zone,
    "delivery_address" "text",
    "delivery_lat" double precision,
    "delivery_lng" double precision,
    "client_comment" "text",
    "scheduled_at" timestamp with time zone,
    "delivery_mode" "text" DEFAULT 'standard'::"text" NOT NULL,
    "delivery_fee_xof" integer DEFAULT 0 NOT NULL,
    "distance_km" numeric,
    "required_vehicle" "text" DEFAULT 'moto'::"text" NOT NULL,
    "accept_code" "text" DEFAULT "public"."gen_code4"() NOT NULL,
    "pickup_code" "text" DEFAULT "public"."gen_code4"() NOT NULL,
    "delivery_code" "text" DEFAULT "public"."gen_code4"() NOT NULL,
    "merchant_confirmed_at" timestamp with time zone,
    "client_confirmed_at" timestamp with time zone,
    "picked_up_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "prescription_id" "uuid",
    "city_code" "text" DEFAULT 'oume'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "address_id" "uuid",
    CONSTRAINT "orders_total_xof_check" CHECK (("total_xof" >= 0))
);

ALTER TABLE ONLY "public"."orders" REPLICA IDENTITY FULL;


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."parcels" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "sender_name" "text" NOT NULL,
    "sender_phone" "text" NOT NULL,
    "sender_address" "text" NOT NULL,
    "sender_lat" double precision,
    "sender_lng" double precision,
    "recipient_name" "text" NOT NULL,
    "recipient_phone" "text" NOT NULL,
    "recipient_address" "text" NOT NULL,
    "recipient_lat" double precision,
    "recipient_lng" double precision,
    "parcel_type" "text" DEFAULT 'autre'::"text" NOT NULL,
    "parcel_weight" "text" DEFAULT 'small'::"text" NOT NULL,
    "notes" "text",
    "price_xof" integer DEFAULT 1000 NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "payment_payer" "text" DEFAULT 'sender'::"text" NOT NULL,
    "payment_method" "text" DEFAULT 'cash'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."parcels" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "parcel_id" "uuid",
    "prescription_id" "uuid",
    "method" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "amount" numeric NOT NULL,
    "currency" "text" DEFAULT 'FCFA'::"text" NOT NULL,
    "phone_number" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prescriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "merchant_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'received'::"public"."prescription_status" NOT NULL,
    "image_paths" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "client_note" "text",
    "delivery_address" "text",
    "delivery_lat" double precision,
    "delivery_lng" double precision,
    "quote_items" "jsonb",
    "products_subtotal_xof" integer,
    "delivery_fee_xof" integer,
    "total_xof" integer,
    "estimated_ready_minutes" integer,
    "pharmacist_note" "text",
    "order_id" "uuid",
    "quoted_at" timestamp with time zone,
    "accepted_at" timestamp with time zone,
    "paid_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "image_url" "text",
    "quote_amount" integer
);

ALTER TABLE ONLY "public"."prescriptions" REPLICA IDENTITY FULL;


ALTER TABLE "public"."prescriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_ratings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "text" NOT NULL,
    "merchant_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "author_name" "text",
    "stars" smallint NOT NULL,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "product_ratings_stars_check" CHECK ((("stars" >= 1) AND ("stars" <= 5)))
);


ALTER TABLE "public"."product_ratings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_suggestions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category" "text" NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "suggested_price_xof" integer,
    "image_url" "text",
    "usage_count" integer DEFAULT 1 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."product_suggestions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "merchant_id" "uuid" NOT NULL,
    "added_by_user_id" "uuid" NOT NULL,
    "added_by_courier_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "price_xof" integer DEFAULT 0 NOT NULL,
    "image_url" "text",
    "category" "text" NOT NULL,
    "is_available" boolean DEFAULT true NOT NULL,
    "stock" integer,
    "city_code" "text" DEFAULT 'oume'::"text" NOT NULL,
    "available_days" "text"[] DEFAULT ARRAY['mon'::"text", 'tue'::"text", 'wed'::"text", 'thu'::"text", 'fri'::"text", 'sat'::"text", 'sun'::"text"] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."products" REPLICA IDENTITY FULL;


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "label" "text" NOT NULL,
    "detail" "text" NOT NULL,
    "lat" double precision NOT NULL,
    "lng" double precision NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."user_addresses" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users_profiles" (
    "id" "uuid" NOT NULL,
    "email" "text" NOT NULL,
    "name" "text",
    "phone" "text",
    "role" "public"."app_role" DEFAULT 'client'::"public"."app_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."users_profiles" OWNER TO "postgres";


ALTER TABLE ONLY "public"."cart_items"
    ADD CONSTRAINT "cart_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."carts"
    ADD CONSTRAINT "carts_client_id_merchant_id_key" UNIQUE ("client_id", "merchant_id");



ALTER TABLE ONLY "public"."carts"
    ADD CONSTRAINT "carts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cities"
    ADD CONSTRAINT "cities_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."cities"
    ADD CONSTRAINT "cities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."couriers"
    ADD CONSTRAINT "couriers_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."merchants"
    ADD CONSTRAINT "merchants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."parcels"
    ADD CONSTRAINT "parcels_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."partner_applications"
    ADD CONSTRAINT "partner_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "prescriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_ratings"
    ADD CONSTRAINT "product_ratings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_suggestions"
    ADD CONSTRAINT "product_suggestions_category_name_key" UNIQUE ("category", "name");



ALTER TABLE ONLY "public"."product_suggestions"
    ADD CONSTRAINT "product_suggestions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_addresses"
    ADD CONSTRAINT "user_addresses_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users_profiles"
    ADD CONSTRAINT "users_profiles_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users_profiles"
    ADD CONSTRAINT "users_profiles_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_couriers_city" ON "public"."couriers" USING "btree" ("city_code");



CREATE INDEX "idx_merchants_category" ON "public"."merchants" USING "btree" ("category");



CREATE INDEX "idx_merchants_city" ON "public"."merchants" USING "btree" ("city_code");



CREATE INDEX "idx_merchants_owner" ON "public"."merchants" USING "btree" ("owner_id");



CREATE INDEX "idx_notif_unread" ON "public"."notifications" USING "btree" ("user_id") WHERE ("read_at" IS NULL);



CREATE INDEX "idx_notif_user" ON "public"."notifications" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_order_items_order" ON "public"."order_items" USING "btree" ("order_id");



CREATE INDEX "idx_orders_city" ON "public"."orders" USING "btree" ("city_code");



CREATE INDEX "idx_orders_client" ON "public"."orders" USING "btree" ("client_id");



CREATE INDEX "idx_orders_courier" ON "public"."orders" USING "btree" ("courier_id");



CREATE INDEX "idx_orders_delivery_mode" ON "public"."orders" USING "btree" ("delivery_mode");



CREATE INDEX "idx_orders_merchant" ON "public"."orders" USING "btree" ("merchant_id");



CREATE INDEX "idx_orders_status" ON "public"."orders" USING "btree" ("status");



CREATE INDEX "idx_partner_applications_status" ON "public"."partner_applications" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "idx_partner_applications_user" ON "public"."partner_applications" USING "btree" ("user_id");



CREATE INDEX "idx_prescriptions_client" ON "public"."prescriptions" USING "btree" ("client_id", "status");



CREATE INDEX "idx_prescriptions_merchant" ON "public"."prescriptions" USING "btree" ("merchant_id", "status");



CREATE INDEX "idx_product_ratings_merchant" ON "public"."product_ratings" USING "btree" ("merchant_id", "created_at" DESC);



CREATE INDEX "idx_product_ratings_product" ON "public"."product_ratings" USING "btree" ("product_id", "created_at" DESC);



CREATE INDEX "idx_products_category" ON "public"."products" USING "btree" ("category");



CREATE INDEX "idx_products_city" ON "public"."products" USING "btree" ("city_code");



CREATE INDEX "idx_products_merchant" ON "public"."products" USING "btree" ("merchant_id");



CREATE INDEX "idx_suggestions_category" ON "public"."product_suggestions" USING "btree" ("category");



CREATE INDEX "idx_user_addresses_user" ON "public"."user_addresses" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "prescriptions_notify" AFTER INSERT OR UPDATE ON "public"."prescriptions" FOR EACH ROW EXECUTE FUNCTION "public"."notify_prescription_change"();



CREATE OR REPLACE TRIGGER "prescriptions_touch_updated_at" BEFORE UPDATE ON "public"."prescriptions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "protect_role_on_update" BEFORE UPDATE ON "public"."users_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."protect_role_column"();



CREATE OR REPLACE TRIGGER "set_updated_at_profiles" BEFORE UPDATE ON "public"."users_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_carts_touch" BEFORE UPDATE ON "public"."carts" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_cities_touch" BEFORE UPDATE ON "public"."cities" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_couriers_touch" BEFORE UPDATE ON "public"."couriers" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_enforce_merchant_open" BEFORE INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_merchant_open_on_order"();



CREATE OR REPLACE TRIGGER "trg_feed_suggestions" AFTER INSERT ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."feed_product_suggestions"();



CREATE OR REPLACE TRIGGER "trg_merchants_updated_at" BEFORE UPDATE ON "public"."merchants" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_notify_order_change" AFTER INSERT OR UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."notify_order_change"();



CREATE OR REPLACE TRIGGER "trg_notify_partner_application" AFTER INSERT OR UPDATE ON "public"."partner_applications" FOR EACH ROW EXECUTE FUNCTION "public"."notify_partner_application_change"();



CREATE OR REPLACE TRIGGER "trg_orders_updated_at" BEFORE UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_partner_applications_updated_at" BEFORE UPDATE ON "public"."partner_applications" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_products_updated_at" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_suggestions_updated_at" BEFORE UPDATE ON "public"."product_suggestions" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_user_addresses_updated" BEFORE UPDATE ON "public"."user_addresses" FOR EACH ROW EXECUTE FUNCTION "public"."touch_updated_at"();



ALTER TABLE ONLY "public"."cart_items"
    ADD CONSTRAINT "cart_items_cart_id_fkey" FOREIGN KEY ("cart_id") REFERENCES "public"."carts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "fk_orders_addresses" FOREIGN KEY ("address_id") REFERENCES "public"."user_addresses"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "fk_orders_couriers" FOREIGN KEY ("courier_id") REFERENCES "public"."users_profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "fk_orders_merchants" FOREIGN KEY ("merchant_id") REFERENCES "public"."merchants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prescriptions"
    ADD CONSTRAINT "fk_prescriptions_merchants" FOREIGN KEY ("merchant_id") REFERENCES "public"."merchants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."parcels"
    ADD CONSTRAINT "parcels_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_parcel_id_fkey" FOREIGN KEY ("parcel_id") REFERENCES "public"."parcels"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_prescription_id_fkey" FOREIGN KEY ("prescription_id") REFERENCES "public"."prescriptions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_merchant_id_fkey" FOREIGN KEY ("merchant_id") REFERENCES "public"."merchants"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users_profiles"
    ADD CONSTRAINT "users_profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "admin deletes merchant" ON "public"."merchants" FOR DELETE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin manages cities delete" ON "public"."cities" FOR DELETE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin manages cities insert" ON "public"."cities" FOR INSERT WITH CHECK ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin manages cities update" ON "public"."cities" FOR UPDATE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin sees all notifications" ON "public"."notifications" FOR SELECT USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin sees all orders" ON "public"."orders" FOR SELECT USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin updates applications" ON "public"."partner_applications" FOR UPDATE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin updates orders" ON "public"."orders" FOR UPDATE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admin views all applications" ON "public"."partner_applications" FOR SELECT USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admins can update any profile" ON "public"."users_profiles" FOR UPDATE USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "admins can view all profiles" ON "public"."users_profiles" FOR SELECT USING ("public"."is_admin"("auth"."uid"()));



CREATE POLICY "anyone reads cities" ON "public"."cities" FOR SELECT USING (true);



CREATE POLICY "anyone reads ratings" ON "public"."product_ratings" FOR SELECT USING (true);



CREATE POLICY "anyone reads suggestions" ON "public"."product_suggestions" FOR SELECT USING (true);



CREATE POLICY "anyone views active merchants" ON "public"."merchants" FOR SELECT USING ((("status" = 'active'::"public"."merchant_status") OR ("auth"."uid"() = "owner_id") OR ("auth"."uid"() = "created_by_courier_id") OR "public"."is_admin"("auth"."uid"())));



CREATE POLICY "anyone views products" ON "public"."products" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "products"."merchant_id") AND (("m"."status" = 'active'::"public"."merchant_status") OR ("m"."owner_id" = "auth"."uid"()) OR ("m"."created_by_courier_id" = "auth"."uid"()))))) OR "public"."is_admin"("auth"."uid"())));



CREATE POLICY "authenticated inserts suggestions" ON "public"."product_suggestions" FOR INSERT WITH CHECK (("auth"."uid"() IS NOT NULL));



CREATE POLICY "authenticated updates suggestions" ON "public"."product_suggestions" FOR UPDATE USING (("auth"."uid"() IS NOT NULL));



CREATE POLICY "cart item owner delete" ON "public"."cart_items" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "public"."carts" "c"
  WHERE (("c"."id" = "cart_items"."cart_id") AND ("c"."client_id" = "auth"."uid"())))));



CREATE POLICY "cart item owner insert" ON "public"."cart_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."carts" "c"
  WHERE (("c"."id" = "cart_items"."cart_id") AND ("c"."client_id" = "auth"."uid"())))));



CREATE POLICY "cart item owner select" ON "public"."cart_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."carts" "c"
  WHERE (("c"."id" = "cart_items"."cart_id") AND ("c"."client_id" = "auth"."uid"())))));



CREATE POLICY "cart item owner update" ON "public"."cart_items" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."carts" "c"
  WHERE (("c"."id" = "cart_items"."cart_id") AND ("c"."client_id" = "auth"."uid"())))));



CREATE POLICY "cart owner delete" ON "public"."carts" FOR DELETE USING (("auth"."uid"() = "client_id"));



CREATE POLICY "cart owner insert" ON "public"."carts" FOR INSERT WITH CHECK (("auth"."uid"() = "client_id"));



CREATE POLICY "cart owner select" ON "public"."carts" FOR SELECT USING (("auth"."uid"() = "client_id"));



CREATE POLICY "cart owner update" ON "public"."carts" FOR UPDATE USING (("auth"."uid"() = "client_id"));



ALTER TABLE "public"."cart_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."carts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "client creates orders" ON "public"."orders" FOR INSERT WITH CHECK (("auth"."uid"() = "client_id"));



CREATE POLICY "client creates prescription" ON "public"."prescriptions" FOR INSERT WITH CHECK (("auth"."uid"() = "client_id"));



CREATE POLICY "client inserts items" ON "public"."order_items" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "order_items"."order_id") AND ("o"."client_id" = "auth"."uid"())))));



CREATE POLICY "client sees own orders" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "client_id"));



CREATE POLICY "client updates own orders" ON "public"."orders" FOR UPDATE USING (("auth"."uid"() = "client_id"));



CREATE POLICY "client updates prescription" ON "public"."prescriptions" FOR UPDATE USING (("auth"."uid"() = "client_id"));



CREATE POLICY "client views prescription" ON "public"."prescriptions" FOR SELECT USING (("auth"."uid"() = "client_id"));



CREATE POLICY "clients can insert own parcels" ON "public"."parcels" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "client_id"));



CREATE POLICY "clients can insert own payments" ON "public"."payments" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "client_id"));



CREATE POLICY "clients can update own parcels" ON "public"."parcels" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "client_id"));



CREATE POLICY "clients can view own parcels" ON "public"."parcels" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "client_id"));



CREATE POLICY "clients can view own payments" ON "public"."payments" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "client_id"));



CREATE POLICY "courier inserts own row" ON "public"."couriers" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "courier reads own row" ON "public"."couriers" FOR SELECT USING ((("auth"."uid"() = "user_id") OR "public"."is_admin"("auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."users_profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'support'::"public"."app_role"))))));



CREATE POLICY "courier sees assigned" ON "public"."orders" FOR SELECT USING ((("auth"."uid"() = "courier_id") OR (("status" = 'accepted'::"public"."order_status") AND ("courier_id" IS NULL))));



CREATE POLICY "courier updates assigned" ON "public"."orders" FOR UPDATE USING ((("auth"."uid"() = "courier_id") OR (("status" = 'accepted'::"public"."order_status") AND ("courier_id" IS NULL))));



CREATE POLICY "courier updates own row" ON "public"."couriers" FOR UPDATE USING ((("auth"."uid"() = "user_id") OR "public"."is_admin"("auth"."uid"())));



ALTER TABLE "public"."couriers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "merchant sees own orders" ON "public"."orders" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "orders"."merchant_id") AND ("m"."owner_id" = "auth"."uid"())))));



CREATE POLICY "merchant updates own orders" ON "public"."orders" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "orders"."merchant_id") AND ("m"."owner_id" = "auth"."uid"())))));



CREATE POLICY "merchant updates prescriptions" ON "public"."prescriptions" FOR UPDATE USING (((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "prescriptions"."merchant_id") AND ("m"."owner_id" = "auth"."uid"())))) OR "public"."is_admin"("auth"."uid"())));



CREATE POLICY "merchant views prescriptions" ON "public"."prescriptions" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "prescriptions"."merchant_id") AND ("m"."owner_id" = "auth"."uid"())))) OR "public"."is_admin"("auth"."uid"())));



ALTER TABLE "public"."merchants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "owner deletes products" ON "public"."products" FOR DELETE USING (((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "products"."merchant_id") AND ("m"."owner_id" = "auth"."uid"())))) OR "public"."is_admin"("auth"."uid"())));



CREATE POLICY "owner inserts own merchant" ON "public"."merchants" FOR INSERT WITH CHECK ((("auth"."uid"() = "owner_id") OR ("auth"."uid"() = "created_by_courier_id")));



CREATE POLICY "owner inserts products" ON "public"."products" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "products"."merchant_id") AND (("m"."owner_id" = "auth"."uid"()) OR ("m"."created_by_courier_id" = "auth"."uid"()))))));



CREATE POLICY "owner updates merchant" ON "public"."merchants" FOR UPDATE USING ((("auth"."uid"() = "owner_id") OR ("auth"."uid"() = "created_by_courier_id") OR "public"."is_admin"("auth"."uid"())));



CREATE POLICY "owner updates products" ON "public"."products" FOR UPDATE USING (((EXISTS ( SELECT 1
   FROM "public"."merchants" "m"
  WHERE (("m"."id" = "products"."merchant_id") AND (("m"."owner_id" = "auth"."uid"()) OR ("m"."created_by_courier_id" = "auth"."uid"()))))) OR "public"."is_admin"("auth"."uid"())));



ALTER TABLE "public"."parcels" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."partner_applications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prescriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_ratings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_suggestions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "support sees all notifications" ON "public"."notifications" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."users_profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'support'::"public"."app_role")))));



CREATE POLICY "support sees all orders" ON "public"."orders" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."users_profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'support'::"public"."app_role")))));



CREATE POLICY "support sees prescriptions" ON "public"."prescriptions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."users_profiles" "p"
  WHERE (("p"."id" = "auth"."uid"()) AND ("p"."role" = 'support'::"public"."app_role")))));



CREATE POLICY "user deletes own addresses" ON "public"."user_addresses" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user deletes own rating" ON "public"."product_ratings" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user inserts own addresses" ON "public"."user_addresses" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "user inserts own application" ON "public"."partner_applications" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "user inserts own notifications" ON "public"."notifications" FOR INSERT TO "authenticated" WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "user inserts own rating" ON "public"."product_ratings" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "user sees own notifications" ON "public"."notifications" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user updates own addresses" ON "public"."user_addresses" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user updates own notifications" ON "public"."notifications" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user updates own rating" ON "public"."product_ratings" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user views own addresses" ON "public"."user_addresses" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user views own application" ON "public"."partner_applications" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."user_addresses" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users can insert own profile" ON "public"."users_profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "users can update own profile" ON "public"."users_profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "users can view own profile" ON "public"."users_profiles" FOR SELECT USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."users_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "view items if can view order" ON "public"."order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."id" = "order_items"."order_id") AND (("o"."client_id" = "auth"."uid"()) OR ("o"."merchant_id" = "auth"."uid"()) OR ("o"."courier_id" = "auth"."uid"()) OR "public"."is_admin"("auth"."uid"()))))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON TABLE "public"."partner_applications" TO "anon";
GRANT ALL ON TABLE "public"."partner_applications" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_applications" TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_partner_application"("_app_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."approve_partner_application"("_app_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_partner_application"("_app_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_merchant_open_on_order"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_merchant_open_on_order"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_merchant_open_on_order"() TO "service_role";



GRANT ALL ON FUNCTION "public"."feed_product_suggestions"() TO "anon";
GRANT ALL ON FUNCTION "public"."feed_product_suggestions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."feed_product_suggestions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gen_code4"() TO "anon";
GRANT ALL ON FUNCTION "public"."gen_code4"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gen_code4"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"("_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"("_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"("_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."merchant_is_open_now"("_merchant_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."merchant_is_open_now"("_merchant_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."merchant_is_open_now"("_merchant_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_order_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_order_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_order_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_partner_application_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_partner_application_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_partner_application_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_prescription_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_prescription_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_prescription_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."protect_role_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."protect_role_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."protect_role_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."reject_partner_application"("_app_id" "uuid", "_note" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."reject_partner_application"("_app_id" "uuid", "_note" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reject_partner_application"("_app_id" "uuid", "_note" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."cart_items" TO "anon";
GRANT ALL ON TABLE "public"."cart_items" TO "authenticated";
GRANT ALL ON TABLE "public"."cart_items" TO "service_role";



GRANT ALL ON TABLE "public"."carts" TO "anon";
GRANT ALL ON TABLE "public"."carts" TO "authenticated";
GRANT ALL ON TABLE "public"."carts" TO "service_role";



GRANT ALL ON TABLE "public"."cities" TO "anon";
GRANT ALL ON TABLE "public"."cities" TO "authenticated";
GRANT ALL ON TABLE "public"."cities" TO "service_role";



GRANT ALL ON TABLE "public"."couriers" TO "anon";
GRANT ALL ON TABLE "public"."couriers" TO "authenticated";
GRANT ALL ON TABLE "public"."couriers" TO "service_role";



GRANT ALL ON TABLE "public"."merchants" TO "anon";
GRANT ALL ON TABLE "public"."merchants" TO "authenticated";
GRANT ALL ON TABLE "public"."merchants" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."parcels" TO "anon";
GRANT ALL ON TABLE "public"."parcels" TO "authenticated";
GRANT ALL ON TABLE "public"."parcels" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "anon";
GRANT ALL ON TABLE "public"."payments" TO "authenticated";
GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT ALL ON TABLE "public"."prescriptions" TO "anon";
GRANT ALL ON TABLE "public"."prescriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."prescriptions" TO "service_role";



GRANT ALL ON TABLE "public"."product_ratings" TO "anon";
GRANT ALL ON TABLE "public"."product_ratings" TO "authenticated";
GRANT ALL ON TABLE "public"."product_ratings" TO "service_role";



GRANT ALL ON TABLE "public"."product_suggestions" TO "anon";
GRANT ALL ON TABLE "public"."product_suggestions" TO "authenticated";
GRANT ALL ON TABLE "public"."product_suggestions" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."user_addresses" TO "anon";
GRANT ALL ON TABLE "public"."user_addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."user_addresses" TO "service_role";



GRANT ALL ON TABLE "public"."users_profiles" TO "anon";
GRANT ALL ON TABLE "public"."users_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."users_profiles" TO "service_role";



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







