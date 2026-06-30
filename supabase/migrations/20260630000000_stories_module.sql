-- =========================================================
-- Module Stories / Publications marchand (FE-21)
-- Ajouté car absent des migrations React/Lovable d'origine :
-- ni le bucket Storage `stories`, ni les colonnes story_images /
-- story_video_url sur `merchants` n'existaient avant. Cette migration
-- les rend officielles et versionnées (jusque-là elles n'existaient
-- que sur la base de test locale du module Marchand).
-- =========================================================

-- 1. Colonnes sur merchants (si pas déjà présentes)
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS story_images text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS story_video_url text;

-- 2. Création du bucket Storage `stories`
-- Public en lecture : les stories sont affichées aux clients sur la
-- fiche commerce (cf. spec FE-06 / 5.3 "Stories / publications").
INSERT INTO storage.buckets (id, name, public)
VALUES ('stories', 'stories', true)
ON CONFLICT (id) DO NOTHING;

-- 3. Policies Storage — même convention que merchant-images :
-- chemin = <user_id>/<fichier>, le marchand ne peut écrire que dans
-- son propre dossier, lecture publique pour l'affichage côté client.

CREATE POLICY "stories_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'stories'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "stories_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'stories'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "stories_delete_own"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'stories'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Lecture publique (anon + authenticated) : nécessaire pour que les
-- clients non connectés puissent voir les stories sur la fiche commerce.
CREATE POLICY "stories_select_public"
ON storage.objects FOR SELECT
USING (bucket_id = 'stories');
