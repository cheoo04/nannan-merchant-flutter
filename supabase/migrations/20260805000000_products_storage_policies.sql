-- =========================================================
-- Policies Storage — bucket `products`
-- Le bucket existait déjà en base (public=true) mais sans policy RLS
-- sur storage.objects, ce qui causait un 403 silencieux à l'upload
-- de photo produit (aucune erreur affichée côté app, cf. échec
-- silencieux de l'écran "Modifier le produit"). Documenté ici pour
-- que les migrations reflètent l'état réel appliqué en base.
-- =========================================================

CREATE POLICY "products_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'products'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "products_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'products'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "products_delete_own"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'products'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Lecture publique : les photos produit sont affichées aux clients
-- sur la fiche commerce, y compris non connectés.
CREATE POLICY "products_select_public"
ON storage.objects FOR SELECT
USING (bucket_id = 'products');
