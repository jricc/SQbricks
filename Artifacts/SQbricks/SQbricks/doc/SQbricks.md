# SQbricks: documentation technique

[Français](SQbricks.md) | [English](SQbricks.en.md)

## Objectif

Ce document complète le `README.md`. Le README donne une entrée rapide dans le
projet ; ce document explique progressivement les choix techniques que nous
validons pendant le travail.

Le premier sujet actuel est le benchmark léger de non-régression. Son objectif
est volontairement limité :

- vérifier que les cas du manifest donnent toujours le statut attendu ;
- vérifier que les cas suivis en performance ne deviennent pas nettement plus
  lents que leur baseline locale ;
- rester lisible ;
- tourner en un temps raisonnable, idéalement moins de 30 minutes.

## Vue d'ensemble de SQbricks

SQbricks est un prototype de recherche pour la vérification de circuits
quantiques hybrides. Un circuit hybride peut combiner opérations quantiques,
mesures et contrôle classique.

Le projet contient deux capacités principales :

- SQbricks-Lift transforme des circuits hybrides afin d'isoler une partie
  unitaire ;
- SQbricks-Verif compare deux circuits unitaires et cherche à établir leur
  équivalence.

Le benchmark léger sert de garde-fou court avant de lancer des campagnes plus
longues. La régression large sélectionnée vérifie un échantillon plus coûteux
mais encore contrôlé. Le benchmark long SQbricks-only reprend les familles
historiques de `scripts/benchmarks.sh`, mais ne conserve que les vérifications
SQbricks dans les CSV produits.

## Commandes du benchmark léger

Les points d'entrée sont dans le `Makefile` :

| Commande | Rôle |
| --- | --- |
| `make regression-light` | Lance le benchmark léger et écrit un CSV de résultat. |
| `make regression-light-baseline` | Produit la baseline locale de la machine. |
| `make regression-light-check` | Compare une nouvelle exécution avec cette baseline. |
| `make tests_regression_light` | Valide le comportement du runner avec un faux SQbricks. |

La baseline est locale à la machine. Elle ne doit pas être versionnée.

La progression est affichée sur `stderr` quand celui-ci est connecté à un
terminal interactif. La barre se réécrit sur une seule ligne et tronque le
libellé si le terminal est trop étroit, afin d'éviter les retours automatiques
à la ligne. `SQBRICKS_LIGHT_PROGRESS=never` désactive cet affichage.

## Manifests

Le benchmark est piloté par deux fichiers :

| Fichier | Rôle |
| --- | --- |
| `scripts/paths/light/pairs.csv` | Comparaisons directes entre deux circuits. |
| `scripts/paths/light/transforms.csv` | Cas où le runner transforme un circuit avant comparaison. |

Chaque ligne indique :

- la suite et le nom du cas ;
- le type de cas (`unit`, `lift`, `owm`, `tele`, `owm_vs_tele`) ;
- le statut attendu en `Sequence` et en `Parallel` ;
- si la performance doit être suivie ;
- le ou les chemins QASM.

La valeur `-` désactive un mode. Par exemple, si `ExpectedParallel` vaut `-`, le
mode `Parallel` n'est pas exécuté pour ce cas.

## Statuts

Les statuts attendus principaux sont :

| Statut | Signification |
| --- | --- |
| `EQ` | équivalence prouvée |
| `NE` | non-équivalence détectée |
| `NC` | inconclusif |
| `TIMEOUT` | limite de temps atteinte |
| `OOM` | limite mémoire atteinte |
| `CRASH` | échec inattendu |
| `PARSE_ERROR` | erreur de parsing |

Si SQbricks réussit mais renvoie une sortie vide ou inconnue, le runner produit
`UNEXPECTED_OUTPUT`. Ce statut échoue toujours : il évite de transformer une
sortie non comprise en résultat acceptable.

## Baseline et check

`make regression-light-baseline` exécute le benchmark et écrit un CSV complet.
`make regression-light-check` relance le benchmark et compare les résultats à
ce CSV.

Le check vérifie deux choses.

Premièrement, chaque ligne exécutée doit conserver son statut attendu. Une
différence de statut est une régression fonctionnelle.

Deuxièmement, les lignes dont `TrackPerformance` vaut `yes` doivent avoir :

- une baseline présente ;
- un temps de baseline positif ;
- exactement un échantillon de temps par round ;
- exactement le même nombre de rounds que l'exécution courante.

Après exécution, le runner demande aussi un temps valide par round pour ces
lignes. Il garde ensuite le meilleur temps observé et le compare à la baseline.
Cela évite qu'un pic de charge local fasse échouer le check alors qu'un round
représentatif est resté proche de la baseline.

Un ralentissement échoue seulement si deux seuils sont dépassés :

- le ratio est supérieur à `SQBRICKS_LIGHT_PERF_THRESHOLD` ;
- le ralentissement absolu est supérieur à
  `SQBRICKS_LIGHT_MIN_SLOWDOWN_SECONDS`.

Cette double condition évite de signaler trop facilement du bruit sur des cas
très courts.

## Sortie CSV

Le CSV complet contient les colonnes utiles à la lecture humaine et au check :

```text
Suite;Case;Kind;Tool;Version;Lift;Opt;ExpectedStatus;ActualStatus;StatusMatch;CH;CS;CZ;CCZ;CCX;CU1;Gates;TimeSeconds;BaselineSeconds;Ratio;PerfStatus;Raw
```

Le champ `Raw` contient le détail des rounds, par exemple :

```text
rounds=3 status=EQ times=[1.000000,1.100000,0.900000] best=0.900000
```

Le runner ne cherche plus à prouver que la baseline correspond exactement au
contenu des fichiers QASM ou à une ancienne définition complète du manifest.
Si le manifest change intentionnellement, la baseline doit être régénérée
localement.

## Tests de validation du runner

`test/benchmarks-light-validation.sh` teste le runner sans lancer le vrai
programme OCaml. Il crée une fixture minimale et place un faux `dune` en tête
de `PATH`.

Le faux `dune` simule deux appels :

- `-nb_gates_csv`, pour renvoyer un comptage de portes stable ;
- `-sqv`, pour renvoyer les sorties configurées par le test.

Les scénarios gardés correspondent au contrat du benchmark léger :

- `--check` exige une baseline ;
- `--check` ne peut pas être combiné avec `--stable` ;
- une baseline doit contenir les temps des cas suivis ;
- les échantillons de performance doivent être complets ;
- une régression fonctionnelle fait échouer le check ;
- une sortie SQbricks inconnue fait échouer le check ;
- un ralentissement significatif fait échouer le check ;
- un seul seuil de performance dépassé ne suffit pas ;
- une baseline invalide ne remplace pas la baseline existante ;
- une baseline valide remplace bien la baseline existante.

Les tests ne couvrent plus les changements de définition détaillés ni les cas
supprimés du manifest. C'est volontaire : ces vérifications rendaient le
benchmark plus difficile à lire que nécessaire pour son objectif actuel.

## Benchmark long SQbricks-only

Le benchmark long est dans `scripts/benchmarks-sqbricks.sh`. Il est proche du
benchmark historique `scripts/benchmarks.sh`, mais il n'appelle pas les outils
de vérification externes comme QCEC, Feynman, PyZX ou AutoQ. Les lignes CSV
produites sont donc des lignes SQbricks.

Les points d'entrée sont :

| Commande | Rôle |
| --- | --- |
| `make benchmark-sqbricks TYPE=owm` | Lance une seule famille. |
| `make benchmarks-sqbricks` | Lance toutes les familles listées dans `LONG_TYPES`. |

Les familles lancées par défaut sont :

```text
sanity-unit sanity-hybrid sanity-partial unit-vs-hybrid veriqc qiskit-hybrid owm tele owm-vs-tele owm-vs-qiskit
```

Les familles `qiskit-hybrid` et `owm-vs-qiskit` utilisent encore
`scripts/qiskit-tr.py` pour générer le circuit transformé, comme dans le
benchmark historique. Qiskit sert ici de générateur de cas, pas de résultat de
vérification externe dans le CSV final.

Chaque famille écrit un fichier séparé :

```text
benchmarks/result/<mois>/benchmarks_sqbricks_<TYPE>_<date>.csv
```

Les limites de ressources sont posées au début du script avec `ulimit` :

- `SQBRICKS_LONG_TIMEOUT`, par défaut `600` secondes de CPU par processus ;
- `SQBRICKS_LONG_MEMORY_KB`, par défaut `7340032`.

Si un cas d'une série ordonnée atteint `TO` ou `OutOfMemory`, les cas plus
grands de la même série ne sont plus exécutés. Une série est identifiée par le
type de benchmark, le dossier source et la famille de nom. Le runner écrit alors
une ligne CSV avec `SKIP_AFTER_RESOURCE_FAILURE` et continue les autres séries.
Par exemple, un échec sur `benchmarks/Feynman/grover_5.qasm` ne saute pas les
cas `benchmarks/VeriQbench/combinational/grover/grover_*.qasm`.

La progression est contrôlée par `SQBRICKS_LONG_PROGRESS=auto|always|never`.
Comme pour le light, elle s'affiche sur `stderr`, se réécrit sur une seule
ligne et ne pollue pas le CSV écrit sur `stdout`.

## Régression large sélectionnée

La régression large sélectionnée est une étape intermédiaire entre le benchmark
léger et le benchmark long complet. Elle ne réutilise pas le runner light :
elle réutilise le runner long SQbricks-only avec des fichiers de chemins plus
courts placés dans `scripts/paths/regression-large/`.

Les points d'entrée actuels sont :

| Commande | Rôle |
| --- | --- |
| `make benchmark-regression-large TYPE=owm` | Lance une seule famille sélectionnée. |
| `make regression-large` | Lance toutes les familles sélectionnées dans `LARGE_TYPES`. |
| `make regression-large-baseline` | Produit les baselines sélectionnées, une par famille. |
| `make regression-large-check` | Relance la sélection et compare les résultats aux baselines. |

État actuel :

- la sélection de chemins existe pour chaque famille du benchmark long ;
- pour les familles ordonnées par taille, elle garde jusqu'à trois plus gros
  représentants afin de ne pas dépendre d'un seul cas qui peut atteindre `TO`
  ou `OutOfMemory` selon l'exécution ;
- le runner écrit des CSV de résultat ;
- les baselines sont stockées par famille dans
  `benchmarks/baseline/regression-large/` ;
- le check est séparé du benchmark léger. Il échoue si une ligne de baseline
  disparaît, si une capacité fonctionnelle est perdue, ou si un temps mesuré
  dépasse à la fois le seuil relatif et le seuil absolu configurés ;
- une amélioration fonctionnelle est signalée mais ne fait pas échouer le check.

## Parser OpenQASM

Le parser OpenQASM traduit les circuits vers `Program.t`, qui utilise des
indices entiers plats pour les qubits et les bits classiques. OpenQASM permet
au contraire plusieurs registres nommés, par exemple :

```qasm
qreg q[1];
qreg r[1];
qreg s[2];
```

Le parser aplatit ces registres en donnant à chacun un offset global :

| Registre | Offset | Taille | Indices SQbricks |
| --- | --- | --- | --- |
| `q` | `0` | `1` | `q[0] -> 0` |
| `r` | `1` | `1` | `r[0] -> 1` |
| `s` | `2` | `2` | `s[0] -> 2`, `s[1] -> 3` |

Le même principe est utilisé pour les registres classiques déclarés avec
`creg`. Les tables `qreg_offsets` et `creg_offsets` stockent donc, pour chaque
nom de registre, le couple `(offset, taille)`.

Les helpers ajoutés dans `Parser_OpenQASM.mly` ont chacun un rôle limité :

- `reset_registers` vide les tables de registres au début d'un parsing, afin
  qu'un fichier QASM ne réutilise pas les déclarations du fichier précédent ;
- `declare_register` enregistre une déclaration `qreg` ou `creg`, réserve une
  tranche consécutive d'indices, puis avance le prochain offset disponible ;
- `register_offset` récupère l'offset d'un registre classique entier, utilisé
  notamment pour les conditions `if (c == n)` ;
- `register_index` traduit `nom[index]` vers `offset + index`.

Par compatibilité avec des bibliothèques QASM existantes, SQbricks accepte aussi
certains registres mal formés au lieu de bloquer immédiatement. Par exemple,
`qreg q[0]; h q[0];` et `qreg q[1]; h q[1];` sont signalés par un warning sur
`stderr`, puis traduits avec l'indice plat `offset + index`. Ce comportement est
une tolérance d'entrée : le circuit reste mal formé, mais SQbricks essaye de le
traiter pour ne pas altérer les jeux de benchmarks externes.

Les instructions `include "...";` sont acceptées pour la compatibilité avec les
fichiers OpenQASM usuels, mais SQbricks ne charge pas le fichier inclus à cette
étape. Les portes supportées sont celles codées directement dans le lexer et le
parser. Si une porte inconnue dépend réellement d'un fichier inclus, elle reste
non supportée.

L'en-tête `OPENQASM 3.0;` est toléré pour certains fichiers de benchmark qui
utilisent en pratique le sous-ensemble legacy ci-dessus. Cela ne signifie pas
que le parser supporte OpenQASM 3 en général.

Les instructions `barrier ...;` sont traitées comme des no-op OpenQASM :
le lexer ignore seulement jusqu'au prochain `;`, puis reprend le parsing. Ce
n'est pas un commentaire `//`, qui ignore tout jusqu'à la fin de la ligne.

La conversion des angles `pi/den` utilise `Parser_help.den_to_k`. Cette
fonction vérifie que `den` est une puissance de deux et retourne l'exposant
correspondant au format SQbricks `2*pi/2^k`. La comparaison des entiers Zarith
se fait avec `Z.equal`, c'est-à-dire par valeur mathématique, pas par identité
mémoire.

## Audit Equiv

L'audit ciblé du pipeline réduction vers équivalence a commencé par la
préparation des paramètres dans `lib/equiv.ml`.

Le premier changement validé évite certaines exceptions non maîtrisées lorsque
les listes d'entrées ou de sorties ne sont pas compatibles. Ces cas renvoient
maintenant un résultat d'équivalence explicite :

- entrées de tailles différentes : `NotEquivDiffInputs` ;
- sorties de tailles différentes : `NotEquivDiffOutputs` ;
- nombre d'entrées et de sorties incompatible : `NotEquivDiffInputsOutputs` ;
- circuit non unitaire dans cette étape : `ErrorCircuitNotUnitary`.

Les tests unitaires correspondants ont été ajoutés dans `test/unitary.ml` pour
les modes `Sequence` et `Parallel`. Les corrections Equiv restantes doivent
continuer sur une branche dédiée après validation des benchmarks de
non-régression.

La migration en cours concerne les erreurs de réduction. Une règle peut ne pas
s'appliquer à un path-sum valide, mais elle peut aussi recevoir un path-sum mal
formé. Ces deux situations ne doivent pas avoir le même retour. Le code introduit
donc un résultat typé pour la réduction, par exemple `Ok path_sum` ou
`Error (MalformedPathSum message)`, puis le propage jusqu'au résultat public
d'Equiv avec `ErrorMalformedPathSum`.

La règle `HH` est le premier cas traité. `Variable_replacement` utilise le même
modèle pour son remplacement principal avec
`Rules.Variable_replacement.variable_replacement` et pour la
normalisation avec `Rules.Variable_replacement.poly_normalized`. Après
validation, ces points d'entrée gardent un nom court mais retournent directement
un résultat typé. Le pipeline de réduction et les tests propagent donc
explicitement `MalformedPathSum` au lieu de s'appuyer sur un wrapper non typé.
`Reduction_algorithm.reduction_algorithm` suit le même principe.

Dans `Equiv`, la construction des états initiaux passe par
`Path_sum.ofSize_init_result`. Une largeur invalide ou un indice
d'initialisation invalide est converti en `ErrorInvalidQubitIndex`, ce qui évite
de laisser remonter `invalid_arg` pendant une vérification.

La comparaison des qubits observables dans `compare_inputs_with_identity` passe
par `Qubit.equal_result`. Une erreur de comparaison indique une métadonnée de
path-sum mal formée et devient `ErrorMalformedPathSum`; les réponses `Ok true`
et `Ok false` gardent le comportement d'équivalence précédent.

La préparation des paramètres vérifie maintenant explicitement
`Program.unitary`. Un programme hybride ou non unitaire, par exemple un circuit
contenant `InitQ`, retourne `ErrorCircuitNotUnitary` avant l'exécution
symbolique.

### Bonne formation des circuits pour Equiv

Avant l'exécution symbolique, `Equiv` distingue trois familles de problèmes :
paramètres d'équivalence invalides, circuits non unitaires, et programmes
unitaires mal formés.

Les listes d'entrées, de sorties et de mesures doivent désigner des qubits
existants. Des longueurs incompatibles entre entrées et sorties retournent
`NotEquivDiffInputs`, `NotEquivDiffOutputs` ou
`NotEquivDiffInputsOutputs`. Un indice hors borne retourne
`ErrorInvalidQubitIndex`.

Un circuit utilisé par le vérificateur d'équivalence doit être unitaire au sens
de `Program.unitary`. Les constructeurs hybrides ou classiques comme `Measure`,
`InitQ`, `It` et `Not` retournent `ErrorCircuitNotUnitary` avant l'exécution
symbolique.

Les applications de portes unitaires doivent ensuite être bien formées :

- les indices de contrôle et de cible doivent être dans la largeur du circuit ;
- une porte qui agit sur une cible, comme `H`, `X` ou `U1`, doit avoir au moins
  une cible ;
- pour ces portes, un contrôle ne doit pas être aussi une cible ;
- l'exposant de `GP` et `U1` doit être positif ou nul.

Une violation de ces contraintes retourne `ErrorInvalidProgram`. Une phase
globale `GP` est un cas particulier : elle peut porter des cibles,
éventuellement avec contrôle. Ces cibles sont validées comme indices, mais elles
n'ont pas d'effet sur l'exécution symbolique. Si `GP` porte à la fois des
contrôles et des cibles, ces listes doivent rester disjointes comme pour les
autres portes.

Les programmes mal formés restent affichables pour le diagnostic :
`Program.String.pretty` utilise une forme générique pour `GP` et `U1` quand
l'exposant est négatif, au lieu de lever une exception pendant l'affichage.

La comparaison symbolique suit maintenant le même principe. Les fonctions
`Qubit.equal_result`, `Poly.Monome.equal_result`, `Poly.equal_result`,
`Path_sum.Ket.equal_result` et `Path_sum.equal_result` distinguent une vraie
réponse d'égalité (`Ok true` ou `Ok false`) d'une comparaison mal formée. Les
cas actuellement typés sont les largeurs incompatibles, les tables de variables
de chemin incomplètes, les listes de sorties de tailles différentes et les
indices de sorties invalides. Les anciennes fonctions `equal` restent des
wrappers de compatibilité qui retournent `false` en cas d'erreur typée. Les tests
unitaires couvrent chaque possibilité observable de ces retours typés.
`Path_sum.equal_result` propage aussi les erreurs typées de comparaison de
phase au lieu de les convertir en simple inégalité.
Dans l'algorithme séquentiel, la décision qui distingue phase nulle, phase
globale et phase conditionnelle utilise aussi `Poly.equal_result`, afin qu'une
comparaison mal formée remonte comme `ErrorMalformedPathSum`.
Les vérifications de séparabilité valident aussi la largeur du ket et les
indices de sortie avant d'extraire les variables ; une incohérence remonte comme
`ErrorInvalidQubitIndex`.
La préparation des permutations internes utilise `Program.Macros.apply_swap_result`
dans `Equiv`, afin qu'une incohérence de tailles de listes ou d'option de
placement ne remonte pas comme `failwith`.
L'inversion interne utilise aussi `Program.inverse_result` : un sous-programme
non réversible est signalé explicitement, puis converti par `Equiv` en
`ErrorCircuitNotUnitary`.

La construction initiale de path-sums suit aussi ce modèle avec
`Path_sum.ofSize_init_result`. La fonction construit l'état initial de largeur
`width`, met à `Zero` les qubits listés dans `inits_0`, puis renumérote les
autres qubits en variables d'entrée `Var 0`, `Var 1`, etc. Elle renvoie
`Error InvalidWidth` si la largeur est négative et `Error InvalidInitIndex` si
un indice de `inits_0` est hors de `[0, width)`. Les tests validés couvrent les
cas sans initialisation, avec une ou plusieurs initialisations, la largeur zéro
et les deux erreurs typées.

La substitution de path-sum est typée avec `Path_sum.substitute_result`. Elle
remplace seulement des variables libres dans la phase et le ket. Une variable
déclarée dans `path_var` est une variable liée de somme : elle ne peut pas être
substituée comme une variable libre. Si la cible est une path variable, la
fonction renvoie `Error CannotSubstitutePathVariable`; avec
`except_path_var=true`, elle protège cette variable et renvoie le path-sum
inchangé. L'ancien `Path_sum.substitute` reste un wrapper de compatibilité.

La lecture de l'ordre des variables de chemin est typée avec
`Path_sum.Ket.path_var_order_result`. Elle reconstruit l'ordre temporaire et
l'ordre final des variables de chemin présentes dans un ket. Elle renvoie
`Error InvalidPathVariableCount` si le nombre de variables déclaré est négatif
et `Error InvalidPathVariableIndex` si le ket contient une variable de chemin en
dehors de l'intervalle déclaré. Ce comportement est plus strict que l'ancien :
un ket qui contient des variables de chemin alors que le nombre déclaré vaut
zéro est maintenant signalé comme mal formé.

Plusieurs opérations locales sur qubits, monômes et polynômes ont aussi reçu un
retour typé :

- `Qubit.remove_result` distingue une suppression effective, une absence de la
  variable et le cas non isolable `CannotRemoveFromSum` ;
- `Poly.Monome.remove_result` propage ce cas sous
  `CannotRemoveQubitSum` ;
- `Poly.Monome.of_qubit_to_result` refuse explicitement un `SumMod2` avec
  `CannotConvertSumMod2` ;
- `Poly.Monome.to_qubit_result` signale les scalaires qui ne représentent pas
  directement un qubit avec `CannotConvertScalarToQubit` ;
- `Poly.to_qubit_result` et `Poly.of_qubit_result` typent les conversions entre
  polynômes et qubits, notamment les sommes modulo 2 non formatées ;
- `Poly.of_qubit_2_pi_result` applique le même contrat de format que
  `Poly.of_qubit_result`, mais utilise le raccourci adapté au cas `2*pi`.

Les anciens wrappers restent en place pendant la migration. Ils conservent le
comportement historique, souvent en levant encore `Failure` ou en retournant
`None`, mais les tests nouveaux ciblent les versions `*_result`.

L'algèbre de polynômes expose maintenant `Poly.distribution_result`. Cette
fonction distribue un monôme sur un polynôme et renvoie
`Error UnformattedDistributionMonome` quand un monôme du polynôme de droite a
un scalaire placé à droite (`Prod (_, Scal _)`). Ce cas levait auparavant dans
`Poly.distribution`. Le wrapper non typé reste disponible pour compatibilité.

Les constructeurs de portes de `Path_sum.Path_sum_library` ont maintenant une
version typée publique. Le contrat commun est simple : une cible, un contrôle ou
un contrôle secondaire hors de la largeur déclarée renvoie
`Error TargetIndexOutOfWidth`. Les anciens constructeurs restent des wrappers de
compatibilité qui préservent le message d'échec historique.

Les constructeurs typés validés sont :

- portes à une cible : `h_result`, `x_result`, `u1_result`, `z_result`,
  `s_result`, `t_result`, `zinv_result`, `sinv_result`, `tinv_result`,
  `rz_result`, `rx_result`, `ry_result` ;
- portes contrôlées : `ch_result`, `cx_result`, `crz_result`, `cz_result`,
  `cs_result`, `ct_result` ;
- portes doublement contrôlées : `ccx_result`, `ccz_result`.

Les helpers internes qui dépendaient de la validation d'indices ont aussi été
typés, notamment `normalisation_factor`, `q2` et `ccrz`.
Ils ne sont pas exposés dans l'interface publique, mais ils permettent aux
constructeurs publics typés de propager l'erreur au lieu de déclencher un
échec non maîtrisé.
