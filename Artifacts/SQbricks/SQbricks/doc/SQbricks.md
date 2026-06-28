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
