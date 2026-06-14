# SQbricks: documentation technique

[Français](SQbricks.md) | [English](SQbricks.en.md)

## Objectif de ce document

Ce document complète le `README.md`.

Le README présente rapidement SQbricks, son installation et ses principales
commandes. Ce document décrit progressivement son architecture et son
fonctionnement interne. Il doit permettre de comprendre :

- à quel besoin répond chaque sous-système ;
- comment une commande traverse les différentes fonctions ;
- quelles données sont produites et consommées ;
- quelles erreurs sont détectées ;
- quels invariants sont protégés par les tests.

La documentation est construite de manière incrémentale. Une fonction y est
ajoutée ou mise à jour après sa revue et sa validation en mode qualité.

## Vue d'ensemble

SQbricks est un outil de vérification de circuits quantiques hybrides. Un
circuit hybride peut combiner des opérations quantiques, des mesures et du
contrôle classique.

Le projet fournit deux capacités principales :

- SQbricks-Lift transforme un circuit hybride afin d'en isoler une partie
  unitaire utilisable par les outils de vérification ;
- SQbricks-Verif compare deux circuits unitaires et cherche à établir leur
  équivalence.

Le benchmark léger de non-régression protège ces capacités sur deux axes :

- la non-régression fonctionnelle : les cas conservent leur statut attendu ;
- la non-régression de performance : les cas suivis ne deviennent pas
  significativement plus lents que leur baseline locale.

## Benchmark léger de non-régression

### Entrées utilisateur

Les cibles suivantes sont définies dans le `Makefile` :

| Commande | Rôle |
| --- | --- |
| `make regression-light` | Exécute le benchmark léger et écrit son résultat CSV. |
| `make regression-light-baseline` | Exécute le benchmark et enregistre une baseline locale. |
| `make regression-light-check` | Compare une nouvelle exécution avec la baseline locale. |
| `make tests_regression_light` | Valide le comportement du runner avec des scénarios synthétiques. |

La baseline dépend de la machine et n'est pas destinée à être versionnée.

### Composants

Le benchmark léger repose notamment sur :

| Fichier | Responsabilité |
| --- | --- |
| `scripts/benchmarks-light.sh` | Exécuter les cas, produire le CSV et effectuer la comparaison avec la baseline. |
| `scripts/paths/light/pairs.csv` | Définir les comparaisons directes entre deux circuits. |
| `scripts/paths/light/transforms.csv` | Définir les cas nécessitant une transformation avant comparaison. |
| `test/benchmarks-light-validation.sh` | Tester le comportement du runner sans lancer de vraie vérification quantique. |

## Validation du runner

### Pourquoi ne pas utiliser le vrai SQbricks ?

Les tests de `test/benchmarks-light-validation.sh` vérifient principalement la
logique de contrôle du runner :

- validation des options ;
- lecture et validation de la baseline ;
- détection des erreurs ;
- gestion des répétitions ;
- classification des résultats.

Ils doivent être rapides et déterministes. Ils exécutent donc le vrai
`scripts/benchmarks-light.sh`, mais remplacent son accès à SQbricks par une
commande simulée.

### Chemin du scénario « check sans baseline »

Le premier scénario documenté vérifie que le mode `--check` refuse de démarrer
sans baseline :

```text
test_check_requires_baseline
    |
    +-- new_fixture
    |     crée un dépôt temporaire minimal
    |
    +-- run_check
          |
          +-- run_fixture_command
                  exécute le vrai benchmarks-light.sh
                  dans l'environnement temporaire
    |
    +-- assert_failed_with
    |     attend le diagnostic "--check requires --baseline"
    |
    +-- assert_no_sqv_run
          vérifie que SQV n'a pas été atteint
```

Le résultat attendu est un échec contrôlé du runner. Cet échec constitue le
succès du test, car il prouve que l'option manquante est rejetée avant le début
des vérifications.

## `new_fixture`

### Rôle

`new_fixture` crée un dépôt temporaire minimal compris par
`benchmarks-light.sh`. Chaque test reçoit son propre environnement isolé.

Elle ne reproduit pas tout le dépôt SQbricks. Elle crée uniquement les fichiers
et dossiers nécessaires au scénario :

```text
fixture.<suffixe-aléatoire>/
|-- benchmarks/
|   |-- a.qasm
|   `-- b.qasm
|-- bin/
|   `-- dune
`-- scripts/
    |-- benchmarks-light.sh
    `-- paths/
        `-- light/
            |-- pairs.csv
            `-- transforms.csv
```

Le suffixe aléatoire est généré par `mktemp` à partir du motif `XXXXXX`. Il
évite que deux tests utilisent le même dossier.

### Cas de benchmark minimal

La fixture configure une seule comparaison directe :

```text
perf;case;unit;EQ;-;yes;benchmarks/a.qasm;benchmarks/b.qasm
```

Elle signifie :

- suite `perf` ;
- cas `case` ;
- comparaison unitaire directe ;
- statut `EQ` attendu en mode `Sequence` ;
- mode `Parallel` désactivé ;
- performance suivie ;
- comparaison de `a.qasm` avec `b.qasm`.

`transforms.csv` ne contient que son en-tête : aucun cas de transformation
n'est nécessaire ici.

Les deux fichiers QASM sont vides. Ils doivent exister et peuvent être utilisés
pour calculer une empreinte, mais leur contenu n'est pas interprété par la
commande simulée.

### Remplacement de Dune

Le runner réel appelle SQbricks sous une forme similaire à :

```bash
dune exec -- ./bin/main.exe -sqv ...
```

La fixture crée un fichier exécutable `bin/dune`. Ce fichier est un script Bash,
ce qui est suffisant : pour le shell, une commande trouvée dans `PATH` peut être
un binaire compilé ou un script exécutable.

Lors de l'exécution, le dossier de la fixture est placé en tête de `PATH` :

```bash
PATH="$fixture/bin:$PATH"
```

Le shell trouve donc le faux `dune` avant le Dune installé sur la machine. Ni
Dune, ni le programme OCaml, ni une véritable vérification quantique ne sont
alors exécutés.

Le faux `dune` accepte seulement les deux opérations utilisées par le runner :

- `-nb_gates_csv` renvoie un comptage de portes déterministe ;
- `-sqv` renvoie les résultats configurés par le test.

Toute autre forme d'appel échoue avec le code `99`. Le test signale ainsi que le
runner utilise désormais une opération qui n'est pas encore simulée.

### Compteur SQV

À chaque appel contenant `-sqv`, le faux `dune` incrémente le fichier indiqué
par `FAKE_COUNTER`. Après trois appels, ce fichier contient `3`.

L'absence du fichier prouve qu'aucun appel SQV n'a été tenté. Dans le scénario
« check sans baseline », c'est un invariant important : la validation des
options doit échouer avant tout travail de vérification.

Le compteur concerne uniquement `-sqv`. Il ne permet pas d'affirmer que le faux
`dune` n'a reçu aucun autre appel, par exemple `-nb_gates_csv`.

### Résultats SQV simulés

`FAKE_SQV_OUTPUTS` contient une liste séparée par des virgules :

```text
1.0,1.0,1.0
```

Le faux `dune` transforme cette liste en tableau et sélectionne une valeur à
chaque appel. Le compteur commence à `1`, tandis que les indices du tableau
commencent à `0`. L'appel numéro `count` utilise donc l'indice `count - 1`.

Dans :

```bash
${FAKE_SQV_OUTPUTS:-1.0,1.0,1.0}
```

`:-` est l'opérateur Bash de valeur par défaut. Il n'existe pas de valeur
numérique `-1.0` dans cette expression.

## `run_check`

### Rôle

`run_check` adapte un scénario de test à `run_fixture_command`. Il ajoute
systématiquement les options :

```text
--check --quiet
```

Ses deux premiers paramètres sont réservés à l'infrastructure du test :

1. le chemin de la fixture ;
2. les sorties successives du faux SQV.

Les paramètres suivants sont des options destinées à
`benchmarks-light.sh`.

### Utilisation de `shift 2`

Copier `$1` et `$2` dans des variables locales ne retire pas ces paramètres.
`shift 2` les supprime de la liste positionnelle après leur lecture.

`"$@"` ne contient alors que les options supplémentaires. Par exemple :

```bash
run_check "$fixture" "1.0,1.0,1.0" --baseline "$baseline"
```

est transmis sous la forme :

```text
--check --quiet --baseline <chemin>
```

Dans le scénario sans baseline, aucune option supplémentaire n'est transmise.
Le runner reçoit uniquement `--check --quiet`.

## `run_fixture_command`

### Rôle

`run_fixture_command` centralise l'exécution contrôlée du vrai
`benchmarks-light.sh`. Elle :

1. entre dans le dépôt temporaire ;
2. prépare les variables d'environnement du runner et du faux `dune` ;
3. lance `benchmarks-light.sh` avec les options du scénario ;
4. capture ses messages dans `run_output` ;
5. capture son code de sortie dans `run_status`.

Cette fonction enregistre ce qui s'est passé. Elle ne décide pas encore si le
test a réussi : cette interprétation appartient aux fonctions d'assertion.

### Environnement temporaire

Les affectations placées directement devant une commande s'appliquent à
l'environnement de cette commande et de ses sous-commandes :

```bash
VARIABLE=valeur commande
```

Les antislashs du script permettent d'écrire cette commande unique sur plusieurs
lignes. Ils ne créent pas plusieurs commandes.

Les variables configurées sont :

| Variable | Consommateur | Rôle |
| --- | --- | --- |
| `PATH` | le shell | Trouver le faux `dune` avant le vrai. |
| `FAKE_COUNTER` | le faux `dune` | Indiquer où compter les appels `-sqv`. |
| `FAKE_SQV_OUTPUTS` | le faux `dune` | Fournir les sorties successives simulées. |
| `SQBRICKS_LIGHT_RUNS` | le runner | Fixer le nombre de répétitions à trois dans la fixture. |
| `SQBRICKS_LIGHT_TIMEOUT` | le runner | Fixer le timeout utilisé par le cas et sa définition. |
| `SQBRICKS_LIGHT_MEMORY_KB` | le runner | Fixer la limite mémoire utilisée par le cas et sa définition. |
| `SQBRICKS_LIGHT_PROGRESS` | le runner | Désactiver la barre de progression pendant les tests. |

Ces affectations ne remplacent pas durablement les variables du shell de
validation. De plus, le bloc `$(...)` s'exécute dans un sous-shell : le
`cd "$fixture"` ne change pas non plus le répertoire du script appelant.

### Sortie et code de retour

L'expression :

```bash
run_output="$(commande 2>&1)"
```

capture la sortie standard et, grâce à `2>&1`, la sortie d'erreur de la
commande.

Après l'exécution :

- `run_output` contient les messages produits par le runner ;
- `run_status` vaut `0` si le runner a réussi ;
- `run_status` est non nul si le runner a échoué.

Un `run_status` non nul n'implique pas automatiquement l'échec du test. Dans un
test de rejet, comme l'absence de baseline, l'échec du runner est le résultat
attendu.

## `test_check_requires_baseline`

### Comportement protégé

Le mode `--check` compare une exécution avec une référence. Sans baseline,
cette comparaison n'a pas de sens. Le runner doit donc refuser la commande
avant toute vérification SQV.

Le test :

1. crée une fixture ;
2. appelle `run_check` sans option `--baseline` ;
3. attend un échec contenant `--check requires --baseline` ;
4. vérifie qu'aucun appel SQV n'a été tenté.

Les sorties simulées `1.0,1.0,1.0` sont fournies parce que l'interface commune
de `run_check` les demande. Elles ne sont jamais consommées dans ce scénario si
le contrôle préalable fonctionne correctement.

### Invariants

Ce test protège deux invariants :

- `--check` nécessite explicitement une baseline ;
- cette erreur de configuration est détectée avant l'exécution de SQV.

## État de la revue

Le point d'entrée du `Makefile` et le chemin d'exécution décrit ci-dessus ont
été documentés pendant la revue du premier scénario.

Les fonctions d'assertion `assert_failed_with` et `assert_no_sqv_run` restent à
examiner fonction par fonction avant de considérer ce premier scénario comme
entièrement revu.
