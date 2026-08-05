-- =========================================================
-- Policies Storage — bucket `prescriptions` (correctif sécurité)
-- Les policies d'origine ("Public Manage" / "Public Upload" /
-- "Public View") accordaient un accès total (SELECT/INSERT/ALL) au
-- rôle `anon`, sans aucune restriction de propriétaire ni de
-- marchand assigné. Concrètement, n'importe qui pouvait lire ou
-- écrire n'importe quelle ordonnance (document médical client),
-- même sans être connecté à l'app.
--
-- Convention de chemin observée en base : <client_id>/<prescription_id>/fichier.jpg
-- (vérifié via `prescriptions.image_paths` avant d'écrire ce correctif).
-- =========================================================

DROP POLICY IF EXISTS "Public Manage" ON storage.objects;
DROP POLICY IF EXISTS "Public Upload" ON storage.objects;
DROP POLICY IF EXISTS "Public View" ON storage.objects;

-- Le client authentifié peut uploader sa propre ordonnance.
CREATE POLICY "prescriptions_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Le client authentifié peut relire sa propre ordonnance.
CREATE POLICY "prescriptions_select_own_client"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'prescriptions'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Le marchand (pharmacien) peut lire les ordonnances qui lui sont
-- assignées, via la jointure prescriptions.merchant_id -> merchants.owner_id.
CREATE POLICY "prescriptions_select_assigned_merchant"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'prescriptions'
  AND EXISTS (
    SELECT 1 FROM public.prescriptions p
    JOIN public.merchants m ON m.id = p.merchant_id
    WHERE m.owner_id = auth.uid()
      AND storage.objects.name = ANY(p.image_paths)
  )
);
