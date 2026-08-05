-- =========================================================
-- Policies Storage — bucket `merchant-images`
-- Même constat que pour `products` : bucket public=true existant en
-- base, mais aucune policy RLS sur storage.objects. Contrairement à
-- products, le code Flutter (uploadShopImage) gère déjà l'échec via
-- try/catch + toast — mais sans policy, l'upload de la photo de
-- couverture boutique échouait systématiquement.
-- =========================================================

CREATE POLICY "merchant_images_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchant-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "merchant_images_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchant-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "merchant_images_delete_own"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchant-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Lecture publique : photo de couverture affichée sur la fiche
-- commerce, y compris aux clients non connectés.
CREATE POLICY "merchant_images_select_public"
ON storage.objects FOR SELECT
USING (bucket_id = 'merchant-images');
