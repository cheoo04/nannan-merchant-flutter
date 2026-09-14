-- Copie de secours du PIN (hash+salt, jamais le PIN en clair) sur
-- users_profiles. Permet de restaurer le Keystore local quand il a été
-- effacé (reset device, purge agressive par certains OEM au reboot),
-- sans forcer une reconfiguration complète du PIN.
--
-- Pas de nouvelle policy RLS nécessaire : les policies existantes sur
-- users_profiles ("users can view own profile" / "users can update own
-- profile", auth.uid() = id) couvrent déjà ces colonnes.

alter table users_profiles
  add column pin_hash text,
  add column pin_salt text,
  add column pin_updated_at timestamptz;
