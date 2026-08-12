-- Corrige approve_partner_application() pour recopier payload.lat/payload.lng
-- vers merchants.lat/merchants.lng lors de la création de la ligne marchand.
--
-- Avant ce correctif, la capture GPS faite côté app à l'inscription
-- (BecomeMerchantScreen) était stockée dans partner_applications.payload
-- mais se perdait silencieusement à l'approbation : aucune colonne lat/lng
-- n'était incluse dans l'INSERT INTO merchants.
--
-- Seule la ligne de l'INSERT INTO merchants change par rapport à la version
-- précédente de cette fonction — tout le reste (permissions, gestion des
-- candidatures livreur, mise à jour du statut) reste strictement identique.

CREATE OR REPLACE FUNCTION public.approve_partner_application(_app_id uuid)
 RETURNS partner_applications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  app public.partner_applications;
  new_role public.app_role;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO app FROM public.partner_applications WHERE id = _app_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF app.status <> 'pending' THEN
    RAISE EXCEPTION 'already_reviewed';
  END IF;

  new_role := CASE WHEN app.type = 'merchant' THEN 'merchant'::public.app_role ELSE 'delivery'::public.app_role END;
  UPDATE public.users_profiles SET role = new_role WHERE id = app.user_id;

  IF app.type = 'merchant' THEN
    INSERT INTO public.merchants (owner_id, name, category, description, address, phone, city_code, status, lat, lng)
    VALUES (
      app.user_id,
      COALESCE(app.payload->>'business_name', 'Mon commerce'),
      COALESCE(app.payload->>'category', 'autre'),
      app.payload->>'description',
      app.payload->>'address',
      app.payload->>'phone',
      COALESCE(app.payload->>'city_code', 'oume'),
      'active'::public.merchant_status,
      (app.payload->>'lat')::double precision,
      (app.payload->>'lng')::double precision
    );
  ELSE
    INSERT INTO public.couriers (user_id, vehicle_type, city_code, is_online)
    VALUES (
      app.user_id,
      COALESCE(app.payload->>'vehicle_type', 'moto'),
      COALESCE(app.payload->>'city_code', 'oume'),
      false
    )
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE public.partner_applications
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  WHERE id = _app_id
  RETURNING * INTO app;

  RETURN app;
END
$function$;
