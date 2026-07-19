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

## Provenance et références

SQbricks a d'abord été développé dans le
[dépôt Qbricks](https://github.com/Qbricks/qbricks.github.io), sous
`Artifacts/SQbricks/SQbricks`. Le présent dépôt place SQbricks à sa racine tout
en conservant l'historique du sous-projet, ses mentions de copyright et sa
licence LGPL 2.1.

Les principales références scientifiques sont :

- Jérome Ricciardi, Sébastien Bardin, Christophe Chareton et Benoît Valiron,
  [*Quantum Circuit Equivalence Checking: A Tractable Bridge From Unitary to
  Hybrid Circuits*](https://arxiv.org/abs/2511.22523), arXiv:2511.22523, 2025 ;
- Jérome Ricciardi,
  [*Practical verification of quantum circuit
  transformations*](https://theses.hal.science/tel-05681895v1/document),
  thèse de doctorat, 2026.

Le prototype d'inspection utilise Quantikz2 pour les circuits LaTeX. La
référence associée est Alastair Kay,
[*Tutorial on the Quantikz Package*](https://arxiv.org/abs/1809.03842),
arXiv:1809.03842. Le fichier [`CITATION.cff`](../CITATION.cff) fournit les
métadonnées de citation de SQbricks.

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
- `SQBRICKS_LONG_MEMORY_KB`, par défaut `6291456`.

Si un mode d'une série ordonnée atteint `TO` ou `OutOfMemory`, ce mode n'est plus
exécuté pour les cas plus grands de la même série. Le runner écrit
`SKIP_AFTER_RESOURCE_FAILURE` pour ce mode, mais continue d'exécuter l'autre.
Un échec de ressource pendant la conversion arrête les deux modes. Une série est
identifiée par le type de benchmark, le dossier source et la famille de nom.
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
- pour les familles ordonnées par taille qui ont une frontière de ressources
  connue, elle garde deux cas stables, le premier cas `TO` ou `OutOfMemory`,
  puis le cas immédiatement supérieur comme repli ;
- le runner écrit des CSV de résultat ;
- les baselines sont stockées par famille dans
  `benchmarks/baseline/regression-large/` ;
- le check est séparé du benchmark léger. Il échoue si une ligne de baseline
  disparaît, si une capacité fonctionnelle est perdue, ou si un temps mesuré
  dépasse à la fois le seuil relatif et le seuil absolu configurés ;
- une amélioration fonctionnelle est signalée mais ne fait pas échouer le check.

Le quatrième cas d'une série est normalement sauté par le cutoff. Il est
exécuté si le cas frontière passe lors d'une nouvelle exécution. Cette marge
maintient la couverture fonctionnelle quand la frontière fluctue, mais elle ne
réduit pas le bruit des mesures de temps.

Le fichier Feynman `benchmarks/Feynman/grover_5.qasm` conserve son nom et sa
provenance sur disque. Le runner utilise toutefois `grover_5_feynman` comme nom
de programme dans les CSV, afin de ne pas créer la même clé que le circuit
VeriQbench également nommé `grover_5`.
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

## Traduction en mesures différées

`To_deferred_measurement.to_deferred_measurements_result` transforme un
programme hybride en programme sans mesures intermédiaires. Elle retourne :

- le programme traduit ;
- la liste des qubits initialisés ;
- la liste des qubits mesurés ;
- ou une erreur typée si la traduction n'est pas supportée.

`to_deferred_measurements` reste le wrapper historique : il appelle la version
typée et lève `Failure` en cas d'erreur, pour garder la compatibilité avec les
anciens appels.

La traduction garde trois états importants :

- `bit_to_qubit` indique quel qubit porte actuellement la valeur classique d'un
  bit. Cette table peut être écrasée quand un même bit classique est réutilisé ;
- `meas` garde tous les qubits déjà mesurés. Cette liste ne doit pas être
  déduite de `bit_to_qubit`, car une réutilisation de bit classique effacerait
  l'information d'une mesure précédente ;
- `used_qubits` garde les qubits déjà utilisés par une porte, une mesure ou une
  correction traduite.

La réutilisation d'un bit classique est donc acceptée. Par exemple, si `c0`
reçoit successivement les mesures de `q0` puis de `q1`, les prochains contrôles
sur `c0` dépendent toujours de la dernière mesure stockée dans ce bit. En
revanche, les deux qubits mesurés restent dans `meas`.

Les corrections classiques sont traduites en contrôles quantiques. Par exemple :

```text
measure q0 -> c0;
if c0 then x q2;
measure q1 -> c0;
if c0 then x q2;
```

devient conceptuellement :

```text
cx q0 q2;
cx q1 q2;
```

Le second `measure` écrase le bit classique `c0`, mais il n'annule pas l'effet
déjà appliqué sur `q2`.

`InitQ` est traité comme l'initialisation d'un qubit frais. Cette forme est
nécessaire pour les traductions MBQC/OWM, qui introduisent des ancillas pendant
la construction du programme. Par exemple :

```text
iq0 1; h 1; iq0 2; h 2
```

est accepté, car `q2` n'a pas encore servi quand il est initialisé. En revanche,
un reset dynamique d'un qubit déjà utilisé n'est pas encore supporté :

```text
x 0; iq0 0
```

retourne `ResetOfUsedQubitUnsupported 0`.

Les erreurs typées actuellement exposées sont :

- `InvalidClassicalBit`, pour un bit classique hors largeur ;
- `InvalidQubitIndex`, pour un qubit hors largeur ;
- `ClassicalControlWithoutMeasurement`, quand un contrôle classique ne contient
  aucun résultat de mesure ;
- `MeasuredQubitUsedAfterMeasurement`, quand une porte réutilise un qubit déjà
  mesuré ;
- `ResetOfUsedQubitUnsupported`, quand `InitQ` vise un qubit déjà utilisé ;
- `UnsupportedConditionalProgram`, pour une forme de conditionnel non traduite.

Le vrai `reset` dynamique OpenQASM et le modèle général `discard` / réutilisation
de qubit restent des points de roadmap. Le comportement validé ici est
conservateur : SQbricks accepte les ancillas fraîches, mais ne prétend pas encore
réinitialiser correctement un qubit déjà actif.

## Audit Equiv

L'audit ciblé du pipeline réduction vers équivalence a commencé par la
préparation des paramètres dans `lib/equiv.ml`.

### Évolution des résultats `Entanglement1`

`Entanglement1` est un résultat inconclusif du contrôle de séparabilité. Après
réduction du premier circuit, il indique que les variables des sorties
observées ne sont pas séparables de celles des qubits éliminés. SQbricks ne
projette donc pas ces qubits et arrête la preuve ; ce résultat ne signifie pas
que les circuits sont non équivalents.

Les résultats longs des 22 au 25 juin 2026 précèdent le commit `e6700a6`, qui
étend le remplacement de variables dans les kets. Le rejeu des cas sur les
commits intermédiaires, puis le retrait séparé de chaque changement, a isolé la
cause des améliorations observées : la substitution descend maintenant dans
les expressions `Qubit.Prod`, alors qu'elle ne parcourait auparavant que les
expressions `Qubit.SumMod2`.

Sans cette branche récursive, une variable à remplacer qui se trouve dans un
produit reste dans le ket réduit. Le contrôle de séparabilité peut alors encore
observer cette variable dans les sorties et les qubits éliminés, puis renvoyer
`Entanglement1`. La substitution sous `Qubit.Prod` permet à la réduction
d'éliminer cette dépendance résiduelle.

Cette correction fait passer `owm/grover_3` en équivalence chronométrée pour
Sequence et Parallel, la vérification Sequence de `owm/grover_5` en équivalence
chronométrée, et sa vérification Parallel à `SubCircuitInconclusive`. Elle fait
aussi passer `owm-vs-tele/grover_3` en équivalence chronométrée et les
vérifications Sequence et Parallel de `owm-vs-qiskit/shor_n5_ancillas`
respectivement en équivalence chronométrée et `SubCircuitInconclusive`.

Le retrait de cette seule branche de `e6700a6` fait réapparaître
`Entanglement1` dans tous ces modes. Inversement, son ajout seul à `3d002fc`
reproduit toutes les améliorations. Elle est donc nécessaire et suffisante pour
ces cas. Les changements qui évitent de modifier des kets partagés restent des
corrections de sûreté. Ni ces changements ni l'appel supplémentaire à
`Qubit.simplify` ne sont nécessaires à ces résultats précis.

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

La règle `HH` retire atomiquement les deux variables de chemin appariées par son
motif. Le facteur produit par la somme destructive compense alors exactement les
deux facteurs de normalisation supprimés. Une variable de chemin inutilisée ne
peut pas être retirée seule : `Elim` n'est donc plus appliquée comme une
réduction indépendante après `HH` ou après la factorisation par remplacement de
variable.

`Rules.Variable_replacement.variable_replacement` accepte une composante de ket
uniquement lorsqu'elle a la forme `y xor Q`, où `y` est une variable de chemin
déclarée qui n'apparaît ni dans `Q`, ni dans la phase, ni dans une autre
composante du ket. `Q` peut contenir un produit indépendant de `y`, par exemple
`y0 xor x0*x1`. En revanche, `x0 xor y0*y1` ne contient pas de candidat direct,
et `y0 xor y0*y1` est refusé parce que `Q` dépend de `y0`.

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
- l'angle effectif de `GP` et `U1` doit être dyadique.

Une violation de ces contraintes retourne `ErrorInvalidProgram`. Une phase
globale `GP` est un cas particulier : elle peut porter des cibles,
éventuellement avec contrôle. Ces cibles sont validées comme indices, mais elles
n'ont pas d'effet sur l'exécution symbolique. Si `GP` porte à la fois des
contrôles et des cibles, ces listes doivent rester disjointes comme pour les
autres portes.

`Program.execution_result` calcule l'angle effectif `s / 2^k`, puis normalise
les angles dyadiques modulo un dans l'intervalle `[0, 1)`. Les coefficients et
les exposants négatifs restent donc valides : `-1/4` devient `3/4`, `5/4`
devient `1/4`, et un angle entier devient `0`, c'est-à-dire l'identité. Un angle
non dyadique retourne `NonDyadicRotationAngle`, converti par `Equiv` en
`ErrorInvalidProgram`.

Le `Program.t` stocké n'est pas réécrit : la normalisation a lieu seulement au
moment de l'exécution symbolique. `Program.String.pretty` conserve donc une
forme générique pour `GP` et `U1` quand l'exposant est négatif, sans lever
d'exception pendant l'affichage. Les macros historiques de `Program.Macros`
continuent toutefois à refuser `k < 0` avant de construire le `Program.t`.

Dans `Poly.Monome.simplify`, les facteurs rationnels sont multipliés exactement
avant de normaliser un coefficient de phase négatif modulo un. Par exemple,
`(-5/4)*(1/2)` est d'abord calculé comme `-5/8`, puis normalisé en `3/8` avec le
reste euclidien. Normaliser `-5/4` avant la multiplication pourrait changer la
phase, car la congruence modulo un n'est pas préservée par une multiplication
rationnelle arbitraire.

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
Sans listes de sorties explicites, `Path_sum.equal_result` compare les kets
complets et retourne `Ok false` si leurs largeurs diffèrent. Avec deux listes de
sorties explicites de même longueur et des indices valides, les largeurs totales
des kets peuvent différer : seules les composantes sélectionnées sont comparées.
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

### Changement de variable de chemin

Cette section suit le formalisme des définitions 2.3.2 à 2.3.4 de la thèse de
Jérôme Ricciardi, *Practical verification of quantum circuit transformations*
([HAL tel-05681895](https://theses.hal.science/tel-05681895)). Cette thèse est
le socle théorique de SQbricks et sert de référence pour la notation et les
preuves ci-dessous.

*Statut : cette formalisation doit encore être relue mathématiquement.*

#### Définition (changement d'une variable de chemin)

Soit le path-sum en forme algébrique suivant :

```text
P = <y, p(x, y), f(x, y)>
y = (y0, ..., y_(m-1))
```

Fixons un indice `k < m` et un polynôme booléen `Q(x, y_except_k)` qui ne
dépend pas de `yk`. Pour une entrée `x`, on définit la fonction
`tau_(k,Q,x) : F_2^m -> F_2^m` par :

```text
tau_(k,Q,x)(y)_i = yi                              si i != k
tau_(k,Q,x)(y)_i = yk xor Q(x, y_except_k)         si i = k
```

Le changement de variable de chemin associé est :

```text
P^(k,Q) = <y,
           p(x, tau_(k,Q,x)(y)),
           f(x, tau_(k,Q,x)(y))>
```

Dans la signature de sortie `f`, la substitution est booléenne. Dans la phase
`p`, elle utilise la transformation d'un polynôme booléen en polynôme
arithmétique de la définition 2.3.2. En notant `lift` cette transformation :

```text
lift(a xor b) = lift(a) + lift(b) - 2 lift(a) lift(b)
```

Cette distinction est nécessaire : remplacer directement `yk` par une
somme arithmétique ferait perdre les termes correctifs produits par le XOR.

On note `P' ≡ P` lorsque les deux path-sums sont sémantiquement équivalents,
c'est-à-dire lorsque :

```text
pour toute entrée x, V(P')(x) = V(P)(x)
```

#### Lemme de correction du changement de variable

Si `Q` ne dépend pas de `yk`, alors le changement de variable produit un
path-sum sémantiquement équivalent :

```text
P^(k,Q) ≡ P
```

**Preuve.** Fixons une entrée `x`. Comme `Q` ne dépend pas de `yk`,
l'application `tau = tau_(k,Q,x)` est une involution. Ses coordonnées autres
que `k` sont inchangées et :

```text
tau(tau(y))_k
  = (yk xor Q(x, y_except_k)) xor Q(x, y_except_k)
  = yk
```

Ainsi, `tau` est une bijection de `F_2^m`. En utilisant la
définition 2.3.4 de la concrétisation, puis le changement d'indice
`z = tau(y)`, on obtient :

```text
V(P^(k,Q))(x)
  = 2^(-m/2) sum_(y in F_2^m)
      exp(2 pi i p(x, tau(y))) |f(x, tau(y))>

  = 2^(-m/2) sum_(z in F_2^m)
      exp(2 pi i p(x, z)) |f(x, z)>

  = V(P)(x)
```

L'égalité vaut pour toute entrée, donc les deux path-sums concrétisent la même
application linéaire. Il s'agit d'une égalité sémantique des concrétisations,
pas nécessairement d'une égalité syntaxique des structures OCaml ni de la
relation de renommage des variables de chemin. Cela démontre le lemme.

#### Corollaire d'isolation correcte d'une variable de chemin

Si une composante de sortie vérifie :

```text
f_j(x, y) = yk xor Q(x, y_except_k)
```

alors :

```text
f_j^(k,Q)(x, y) = yk
P^(k,Q) ≡ P
```

**Preuve.** Les coordonnées différentes de `k` ne sont pas modifiées par
`tau`. L'indépendance de `Q` par rapport à `yk` donne donc :

```text
f_j(x, tau(y))
  = (yk xor Q) xor Q
  = yk
```

La préservation de la concrétisation découle du lemme, ce qui démontre le
corollaire.

Le lemme autorise tout polynôme booléen `Q` indépendant de `yk`. Pour corriger
le cas `owm-vs-qiskit/dqc_teleportation` sans généraliser prématurément,
`Rules.Variable_replacement.replace_not_path_var_by_var` reconnaît seulement
une forme affine construite à partir des variables d'entrée :

```text
Q(x) = c xor (xor_(i in I) xi), avec c dans F_2
```

Cela comprend par exemple `1`, `x0`, `x0 xor x2` et `1 xor x0 xor x2` ;
`Q = 0` est l'identité et ne demande aucune réécriture. Les produits comme
`x0 x1` et les décalages qui contiennent une autre variable de chemin restent
hors de cette implémentation. Cette restriction est une décision
d'implémentation, pas une condition du lemme.

Une substitution reconnue est appliquée à toute la phase et à tout le ket,
pas uniquement à la composante qui a permis de la détecter. À chaque appel, la
fonction applique au plus un changement, et seulement s'il augmente le nombre
de composantes de sortie exactement égales à la variable de chemin. Elle ne
fait donc pas un changement qui déplacerait simplement la même expression vers
une autre composante.

Deux exemples fixent les résultats attendus par les tests :

**Exemple 1 : `owm-vs-qiskit/dqc_teleportation`.**

```text
P = <(y0, y1),
     1/2 x1 y0 + 1/2 x2 y1,
     (y0, x0 xor x1 xor y1, x0 xor x1)>

Changement : y1 <- y1 xor x0 xor x1

P' = <(y0, y1),
      1/2 x0 x2 + 1/2 x1 x2 + 1/2 x1 y0 + 1/2 x2 y1,
      (y0, y1, x0 xor x1)>
```

La phase de `P'` est simplifiée modulo les polynômes à coefficients entiers.

**Exemple 2 : simplification avec un coefficient de phase `1/4`.**

```text
P = <y0,
     1/4 x0 + 1/4 y0 + 1/2 x0 y0,
     (x0 xor y0)>

Changement : y0 <- y0 xor x0

P' = <y0, 1/4 y0, (y0)>
```

Dans la phase de `P`, le coefficient `+1/2` est équivalent à `-1/2` modulo un
coefficient entier. Cet exemple vérifie que la substitution utilise bien le
coefficient `1/4` du contexte : la phase et le ket sont tous les deux
simplifiés.

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

`Qubit.extract_var` et `Qubit.extract_path_var` parcourent récursivement les
produits et les sommes modulo deux avec un accumulateur. Les constantes `Zero`
et `One` n'ajoutent aucune variable, mais elles conservent les variables déjà
collectées dans une autre branche de l'expression.

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

Pour `u1_result`, `rz_result`, `rx_result` et `ry_result`, le coefficient `s`
est un entier. Un exposant `k < 0` donne donc exactement l'identité : la phase
est nulle, la cible reste inchangée et aucune variable de chemin n'est créée.
`u1_result` donne aussi l'identité pour `k = 0`. Ce cas est distinct d'un
coefficient `s < 0`, qui reste un angle négatif valide. Les tests couvrent les
quatre constructeurs et vérifient notamment que `rx_result` et `ry_result`
retournent `path_var = []`.

Les helpers internes qui dépendaient de la validation d'indices ont aussi été
typés, notamment `normalisation_factor`, `q2` et `ccrz`.
Ils ne sont pas exposés dans l'interface publique, mais ils permettent aux
constructeurs publics typés de propager l'erreur au lieu de déclencher un
échec non maîtrisé.

## Prototype d'inspection

Le prototype d'inspection de la phase 9 est fourni par
`scripts/inspect-sqbricks.sh`. Il ne modifie pas le coeur OCaml : il orchestre
les commandes existantes de SQbricks pour rendre une comparaison plus facile à
lire.

Le script prend deux fichiers QASM et fonctionne en deux modes :

- `--mode auto` appelle le workflow SQbricks automatique avec `-sq` ;
- `--mode manual` appelle `-sqv` avec les métadonnées explicites
  (`inputs`, `outputs`, `meas`, algorithme et relation d'équivalence).

SQV est lancé avec `verbose=true` parce que l'objectif du script est
l'inspection, pas la mesure compacte. La trace complète est conservée dans
`sqv.stdout`. Le script extrait aussi les path-sums finaux depuis cette trace.
Cette extraction dépend donc encore du format texte de debug actuel ; ce n'est
pas une interface OCaml stable.

Par défaut, les résultats sont écrits dans `_tmp/inspection/<timestamp>/`.
Les fichiers importants sont :

- `report.txt` : résumé lisible de l'exécution ;
- `commands.sh` : commandes rejouables ;
- `sqv.stdout` et `sqv.stderr` : trace complète de SQV ;
- `pathsum-left.stdout` et `pathsum-right.stdout` : path-sums des deux entrées ;
- `final-path-sums.txt` : path-sums finaux extraits de SQV ;
- `circuit-left.tex`, `circuit-right.tex`, `circuits.tex` et `circuits.pdf` :
  export prototype des circuits avec Quantikz2 quand ils sont assez petits ;
- `pathsum-left.tex`, `pathsum-right.tex`, `final-path-sums.tex` et
  `path-sums.tex` : export LaTeX prototype ;
- `path-sums.pdf` : PDF compilé si `pdflatex` est disponible.

L'export LaTeX sépare chaque path-sum en trois parties :

- `p`, affiché comme un tableau de monômes numérotés sur deux colonnes ;
- `f`, affiché comme un tableau de composantes de sortie numérotées par qubit ;
- `Y`, affiché séparément pour les variables de chemin.

Les path-sums trop grands peuvent être ignorés par l'export LaTeX afin d'éviter
de saturer LaTeX. Le seuil est contrôlé par
`SQBRICKS_INSPECT_LATEX_MAX_CHARS` et vaut `30000` caractères par défaut.

L'export circuit est volontairement limité. Il lit les circuits OpenQASM 2
simples, produit du LaTeX Quantikz2, et saute le dessin si le nombre de qubits
ou de portes dépasse les seuils `SQBRICKS_INSPECT_CIRCUIT_MAX_QUBITS` et
`SQBRICKS_INSPECT_CIRCUIT_MAX_GATES`. Cette limite évite de produire des PDF
illisibles ou trop lourds pendant l'inspection.
Les circuits trop larges sont coupés en plusieurs blocs Quantikz2 dans un
document paysage. Le nombre maximal de colonnes par bloc est contrôlé par
`SQBRICKS_INSPECT_CIRCUIT_WRAP_GATES`, avec une valeur par défaut de `12`.
Les bits classiques écrits par les mesures simples `measure q[i] -> c[j]` sont
dessinés comme des fils classiques et reliés à leur mesure.
Les définitions de portes personnalisées ne sont pas développées ; le script
se contente d'ignorer leur corps et de simplifier les appels qu'il ne sait pas
dessiner précisément.
L'image Docker installe la bibliothèque TikZ Quantikz2 courante depuis CTAN
dans une couche finale.

La suite prévue de cette phase est une interface graphique qui permettra de
charger deux fichiers QASM, modifier les métadonnées, choisir le mode
auto/manual, lancer SQV et parcourir les artefacts générés.
