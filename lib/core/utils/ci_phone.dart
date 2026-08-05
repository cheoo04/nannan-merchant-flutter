// Validation/normalisation téléphone ivoirien + génération de l'email de
// secours utilisé pour l'auth Supabase quand le marchand n'a pas d'email.
// Partagé entre SignupScreen (création) et LoginScreen (reconnexion) —
// la génération est déterministe (même téléphone → même email de secours),
// donc pas besoin de lookup en base pour reconnecter un compte "téléphone
// seul" : on régénère simplement le même email à partir du numéro tapé.

class CiPhone {
  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'[\s\-]'), '');

  static bool isValid(String raw) {
    final n = normalize(raw);
    return RegExp(r'^0\d{9}$').hasMatch(n);
  }
}

// Jamais affiché, jamais utilisé pour contacter qui que ce soit, et jamais
// stocké dans users_profiles.email (qui reste null pour ces comptes) —
// uniquement un identifiant technique pour Supabase Auth.
String placeholderEmailForPhone(String normalizedPhone) =>
    '$normalizedPhone@nannan-marchand.local';
