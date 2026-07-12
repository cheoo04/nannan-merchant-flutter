/// Registre centralisé des métiers marchand.
///
/// Pourquoi ce fichier existe :
/// `merchants.category` est un champ TEXTE LIBRE en base (pas d'ENUM, pas de
/// contrainte). Deviner le métier depuis ce texte (ex: `.contains('pharma')`)
/// est fragile — "Parapharmacie" matcherait à tort, "Officine" ne matcherait
/// pas du tout. Ce fichier est le SEUL endroit où cette détection doit vivre :
/// si tu ajoutes un métier avec un comportement spécial (comme le flux
/// ordonnance), fais-le ICI et nulle part ailleurs dans l'app marchand.
///
/// ⚠️ Limite connue : tant que `merchants.category` reste un texte libre non
/// contraint en base, cette détection restera une heuristique, pas une
/// garantie. La solution propre (champ booléen `requires_prescription` fixé
/// explicitement par l'admin à la validation du partenaire, ou table
/// `business_categories`) est hors du périmètre "code marchand" — à discuter
/// séparément avant de toucher à l'inscription / validation partenaire.
library merchant_category;

class MerchantCategoryInfo {
  final String code;
  final String label;
  final bool needsPrescriptionFlow;

  const MerchantCategoryInfo({
    required this.code,
    required this.label,
    required this.needsPrescriptionFlow,
  });
}

/// Un seul endroit pour dire "ce métier a le flux ordonnance".
/// Ajouter un nouveau métier avec ce flux = ajouter une ligne ici,
/// rien à toucher ailleurs (nav bar, produits, dashboard s'adaptent seuls).
const List<MerchantCategoryInfo> kMerchantCategories = [
  MerchantCategoryInfo(code: 'pharmacie', label: 'Pharmacie', needsPrescriptionFlow: true),
  MerchantCategoryInfo(code: 'maquis', label: 'Maquis', needsPrescriptionFlow: false),
  MerchantCategoryInfo(code: 'boutique', label: 'Boutique', needsPrescriptionFlow: false),
  MerchantCategoryInfo(code: 'marche', label: 'Marché', needsPrescriptionFlow: false),
  MerchantCategoryInfo(code: 'boulangerie', label: 'Boulangerie', needsPrescriptionFlow: false),
  MerchantCategoryInfo(code: 'gaz', label: 'Gaz', needsPrescriptionFlow: false),
];

/// Détection à partir du texte libre stocké en base.
/// Match exact d'abord (fiable), puis repli sur une recherche de mot-clé
/// (utile tant que la saisie marchand n'est pas contrainte à une liste fermée).
/// "parapharmacie" est explicitement exclue : elle contient "pharma" mais ne
/// délivre pas sur ordonnance — exactement le piège que ce fichier évite.
bool categoryNeedsPrescriptionFlow(String? rawCategory) {
  final v = (rawCategory ?? '').trim().toLowerCase();
  if (v.isEmpty) return false;

  final exact = kMerchantCategories.where((c) => c.code == v);
  if (exact.isNotEmpty) return exact.first.needsPrescriptionFlow;

  if (v.contains('parapharma')) return false; // exclusion explicite, voir doc ci-dessus
  if (v.contains('pharma')) return true;

  return false;
}