# Audit initial — École Privée Les Étoiles

Date : 29 octobre 2026  
Branche de travail : `audit-uiux-2026-10-29`  
Cible analysée : `index.html` sur `main`, puis ajustements CSS limités sur la branche d'audit.

## Portée et limites

Cet audit initial est fondé sur l'inspection statique du code source accessible dans le dépôt. L'accès du connecteur Supabase a refusé les requêtes d'inspection des tables, migrations et conseillers de sécurité avec une erreur de permission. La page de production n'a pas pu être chargée par l'outil de navigation dans cette session. Par conséquent, aucun test d'exécution dans un navigateur, aucune vérification réelle des politiques RLS et aucun test de données n'est déclaré comme réussi.

Les constats ci-dessous sont séparés entre observations du code, risques à vérifier et éléments bloqués. Aucune donnée de production ni politique de base de données n'a été modifiée.

## Constats confirmés par inspection du code

| ID | Priorité | Constat | Risque / conséquence | Remédiation |
|---|---|---|---|---|
| UI-01 | P2 | L'application est principalement contenue dans un seul fichier `index.html` d'environ 186 Ko avant les améliorations. Le fichier regroupe styles, vues et logique applicative. | Maintenance, revue et tests de régression plus difficiles. | Conserver une modernisation progressive ; extraire les styles et modules seulement dans une évolution testée. |
| UI-02 | P2 | Le style principal est dans un seul bloc CSS, avec des règles mobiles répétées et quelques points de rupture. | Risque d'incohérence visuelle entre vues et tailles d'écran. | Ajout sur la branche d'audit de tokens de design, d'états de focus, de styles de survol, de hiérarchie de composants et de règles ciblées pour petits écrans. |
| UI-03 | P2 | La palette existante est basée sur un bleu nuit (#152b4a), un bleu (#245ca6) et un or (#eab84b). | Une refonte qui introduirait des couleurs sans lien avec l'identité existante diluerait la marque. | Conserver cette palette dans les styles proposés ; valider ensuite les nuances à partir du logo officiel fourni par l'école. |
| UI-04 | P2 | La navigation mobile utilise des onglets horizontaux défilants. | Certains utilisateurs peuvent ne pas découvrir immédiatement les sections qui sortent de l'écran. | Amélioration du défilement, du repérage au focus et de l'espacement tactile ; un test manuel reste nécessaire sur iPhone. |
| UI-05 | P2 | Les tableaux utilisent une largeur minimale et des conteneurs défilants. | Sur téléphone, la consultation nécessite parfois un défilement horizontal. | Conserver le défilement pour éviter la perte de colonnes, améliorer la scrollbar et le focus clavier ; envisager ultérieurement des vues en cartes adaptées aux petits écrans. |
| SEC-01 | À vérifier / P1 potentiel | Le code construit de nombreuses portions d'interface avec `innerHTML`. Une fonction `escapeHtml` est présente et plusieurs champs dynamiques visibles sont échappés, mais un relevé statique ne suffit pas à confirmer chaque chemin de données. | Une interpolation non échappée d'une valeur non fiable pourrait produire une faille XSS. | Revoir toutes les interpolations, privilégier `textContent` ou des nœuds DOM pour les données non fiables, puis tester les champs avec caractères spéciaux dans un environnement isolé. |
| SEC-02 | Bloqué | Les tables, politiques RLS, privilèges, vues, fonctions et migrations Supabase n'ont pas pu être inspectés via le connecteur durant cette session. | Impossible de conclure sur la sécurité réelle des données scolaires. | Réexécuter l'audit avec un accès de lecture autorisé ; ne pas modifier la production à l'aveugle. |
| QA-01 | Bloqué | Le navigateur de cette session n'a pas pu récupérer la page de production et aucun compte de test n'a été fourni dans cet environnement. | Le comportement en production, l'authentification et les workflows n'ont pas été validés. | Effectuer les tests manuels avec un compte de test et un navigateur, sans toucher aux dossiers réels. |
| QA-02 | P1 potentiel | Le front-end utilise Supabase et une clé publique destinée au client. Sa présence n'est pas, à elle seule, une exposition de secret. | La sécurité dépend de la configuration des politiques serveur et des autorisations. | Confirmer les politiques RLS et les privilèges avec un accès autorisé ; ne jamais intégrer de clé de service dans le navigateur. |

## Modifications UI/UX réalisées sur la branche d'audit

Le fichier `index.html` a reçu uniquement des ajouts CSS non destructifs :

- harmonisation des variables de couleurs, surfaces, rayons et ombres ;
- typographie système avec une hiérarchie plus cohérente ;
- états de focus visibles pour clavier et formulaires ;
- états de survol et d'activation plus cohérents ;
- amélioration de la lisibilité des tableaux et du survol des lignes ;
- ajustements du menu, des tableaux, des formulaires et des composants de communication sur mobile ;
- prise en charge de `prefers-reduced-motion` ;
- amélioration des états de focus des boutons et des champs.

Ces changements n'ont pas modifié les requêtes Supabase, les règles métier, les formulaires HTML ou les données. Ils restent à valider visuellement dans un navigateur avant toute mise en production.

## Tests exécutés

- [x] Récupération du fichier source `index.html` depuis la branche `main`.
- [x] Inspection statique des styles, des vues et de plusieurs usages de `innerHTML`.
- [x] Création d'une branche de travail distincte de `main`.
- [x] Application d'un ajout CSS ciblé sur cette branche.
- [ ] Test navigateur de toutes les vues.
- [ ] Test responsive réel sur iPhone et ordinateur.
- [ ] Tests de connexion et de permissions.
- [ ] Tests de non-régression des formulaires, imports et exports PDF.
- [ ] Audit Supabase/RLS et tests d'accès non autorisés.
- [ ] Validation de la génération et de l'impression des documents.

## Prochaine séquence recommandée

1. Examiner le diff et valider les changements visuels en prévisualisation.
2. Tester les parcours principaux avec un compte de test.
3. Obtenir un accès de lecture autorisé à Supabase et inspecter RLS, privilèges et migrations.
4. Revoir les interpolations `innerHTML` et corriger les éventuels chemins non échappés.
5. Corriger les anomalies confirmées par ordre P0 → P1 → P2 → P3.
6. Fusionner et déployer uniquement après validation humaine.

## État de préparation

**Statut : prêt pour revue technique et prévisualisation, pas encore validé pour production.**

La branche contient des améliorations visuelles ciblées. L'audit fonctionnel et de sécurité demeure incomplet tant que les tests navigateur et l'inspection autorisée de Supabase n'ont pas été effectués.
