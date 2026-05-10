# Résultats benchmark matchigo-lua

[English](./README.md) · 📖 Français

Sortie de bench live et reproductible pour les dispatchers de pattern-matching
de matchigo-lua, comparés à du Lua natif écrit à la main (chaînes `if/elseif`
et tables `t[key]`).

> [!IMPORTANT]
> **Ces chiffres ne reflètent pas la réalité en prod.** Ils sont délibérément
> mesurés dans des boucles serrées à l'échelle de la microseconde avec des
> inputs cyclés pour faire ressortir l'overhead per-call de *l'abstraction*.
> Dans n'importe quelle application réelle, un ratio 2–5× ici est du bruit
> invisible à côté des appels HTTP, des requêtes DB, du file IO, ou même
> d'une simple allocation de table Lua dans votre handler de requête.
>
> Choisissez un dispatcher sur la **lisibilité**, la **maintenabilité**,
> et **comment le code se relit dans six mois**. Pas sur ces ratios. Le
> bench vous dit ce que coûte le dispatch ; seul votre profiler vous dit
> si ça importe pour *votre* app.

---

## Ce qu'il y a dans ce dossier

| Fichier | Quoi |
|---|---|
| [`matrix.md`](./matrix.md) | Aggrégat cross-runtime. Une ligne par benchmark, une colonne par runtime Lua/LuaJIT. Chaque cellule : `mean · alloc · ratio_vs_native`. |
| [`runtime-5.3.md`](./runtime-5.3.md) | Tableaux per-scenario détaillés pour Lua 5.3. Inclut `min..max`, `p50/p99`, allocation par appel, et compteur d'outliers GC. |
| [`runtime-5.4.md`](./runtime-5.4.md) | Idem, Lua 5.4. |
| [`runtime-luajit-2.1.md`](./runtime-luajit-2.1.md) | Idem, LuaJIT 2.1. |
| `.stats/*.lua` | Stats brutes consommées par `bench/matrix.lua`. Pas commit. |

Le matrix est **découplé du benchmarking** : faites tourner `bench/run.lua`
sous les interpréteurs que vous avez, déposez leurs stats dans `.stats/`,
puis aggregez à n'importe quel moment via `lua bench/matrix.lua` — pas
besoin de re-bench.

---

## Comment lire le matrix

Chaque cellule se lit `mean · alloc · ratio_vs_native` :

- **mean** — temps moyen par appel (cyclage à travers des inputs variés à chaque itération)
- **alloc** — bytes alloués par appel (zéro pour les hot paths, > 0 quand le
  dispatcher construit des tables / closures / bindings)
- **ratio** — relativement au baseline *native* dans le même runtime

Native est le baseline dans chaque groupe. La ligne matchigo reporte combien
d'overhead l'abstraction ajoute (ou, sur les scenarios à hash, combien elle
fait gagner) sur ce VM spécifique.

### Lire la bonne colonne

Les runtimes différents racontent des histoires différentes :

- **Lua 5.3 / 5.4** (no JIT) : coût de dispatch honnête. Chiffres stables,
  ratios reflètent l'overhead réel de l'abstraction au niveau interpréteur.
- **LuaJIT 2.1** : le JIT inline agressivement. Les ratios proches de `1.0×`
  sur les pure-dispatch sont réels — le JIT a compilé les deux contestants
  en code machine quasi identique. Le signal qui survit à l'optimisation JIT
  est l'**allocation**, donc la colonne alloc importe plus que la colonne ns
  sur LuaJIT.

> [!NOTE]
> Le bench cycle à travers des inputs variés à chaque itération pour défaire
> le constant folding et le loop-invariant code motion de LuaJIT. Sans
> cyclage, les deux contestants reporteraient `0 ns` sous LuaJIT peu importe
> le dispatcher — le JIT prouverait correctement que l'appel est gratuit
> avec un input prédictible. Le scenario dédié **JIT folding showcase** garde
> volontairement un input constant pour démontrer cet effet, comme ça vous
> voyez le contraste.

---

## Quand matchigo gagne, égale, perd

### matchigo gagne

- **Longues chaînes `if/elseif`** (≥ 20 branches). Le dispatch hash compilé
  de matchigo est `O(1)` ; la chaîne native est `O(n)`. Le gain le plus
  clair est le scenario `50-branch literal dispatch — tail hits + fallback`.
- **Rules data-driven** construites à partir d'un config / DB / input
  runtime. Native doit fabriquer son propre hash, matchigo consomme juste
  le tableau de rules.
- **Unions discriminées avec destructuring**. matchigo extrait les champs
  et valide leur shape en une seule étape déclarative ; native imbrique
  `if e.kind ==` + lectures de champ manuelles.

### matchigo égale

- Petits dispatchs (3–5 branches avec littéraux simples). Native et le
  dispatch hash de matchigo se retrouvent au même coût per-call sur tous
  les runtimes.
- Hash table dispatch fait à la main vs `m.compile()` à partir des mêmes
  données. Les deux sont `O(1)` ; l'écart se ferme dans le bruit.

### matchigo perd

- Shape matching inline tight comme `if e.kind == "click"` suivi de
  `e.x` / `e.y`. Native, c'est juste deux lectures de champ ; matchigo
  doit walk le shape descriptor. Comptez 1.5–3× plus lent.
- Guards numériques tight avec bornes constantes. Native `if n < 10` est
  une comparaison ; `P.lt(10)` est un appel de closure.
- L'API chainée `matcher() + DSL` sur les scenarios chargés en guards.
  Le DSL est zero-overhead **au compile time** mais la machinerie des
  guards et les closures de binding coûtent 4–7× de plus par appel que
  `compile()` pour la même logique. Utilisez le DSL pour l'ergonomie ;
  prenez `compile()` pour les vrais hot paths.

---

## Roadmap perf

> [!IMPORTANT]
> **matchigo-lua v1.0 ship la version lisible, pas la version max.** Les
> internals privilégient un modèle de compile clair + une maintenance
> simple plutôt que des ns au pic. Ce qu'il y a dans le matrix au-dessus,
> c'est l'état **actuel** du dispatcher, pas sa **performance maximale
> atteignable**.

Les chiffres qu'on publie sont le plancher de "à quoi ressemble une v1
raisonnable", pas le plafond. Les leviers concrets pas encore tirés :

### Spécialiser la rule list en source Lua (le gros)

Aujourd'hui, `m.compile(rules)` compose des closures à runtime — une par
`_test`, une par handler, plus la coque de dispatch. Chaque appel walk
au moins une frontière de closure. Le gain qui attend sur la table :
**émettre une seule string de source `function(v) ... end` Lua par rule
list au moment de la construction, puis `load(src)` dessus**.
Concrètement, un JIT-at-construction.

Le body émis connaît les rules statiquement et peut :

- Inliner chaque `_test` dans le body — pas d'appel de closure au dispatch.
- Matérialiser les bindings comme locals inline (`local x, y = v.x, v.y`)
  au lieu d'allouer une table de binding `{ x = ..., y = ... }` par appel.
- Spécialiser les clés de hash quand les littéraux sont connus.

Impact attendu : ferme la majorité de l'écart 1.2–1.5× sur `compile()` ;
l'overhead d'allocation `matcher + DSL` disparaît entièrement sur les
scenarios shape-avec-binding.

### Recycler les tables de binding

Là où l'émission de source n'est pas possible (guards DSL qui ont besoin
de closures, ou patterns vraiment dynamiques), réutiliser une seule table
de binding scratch par rule au lieu d'allouer fresh. Échange un peu
d'analyse de liveness au compile-time contre zéro alloc per-call.

### Aplatir les couches wrapper

Aujourd'hui `compile()` retourne une closure qui appelle dans le
dispatcher qui appelle le handler. Trois call frames. Avec l'émission
de source, ça s'effondre en un — le dispatcher *est* la fonction
retournée, l'appel du handler est inliné où c'est statiquement connu.

### Micro-opts d'itération

- Remplacer `ipairs(rules)` par `for i = 1, #rules` dans le rule walker
  (petit gain sur PUC Lua, pas d'impact sur LuaJIT, mais gratuit).
- Pré-résoudre `pat._test` en upvalues au compile-time pour que le
  dispatcher lise depuis un tableau d'upvalues plat au lieu de fetcher
  les champs par appel.

### Locals plus tôt, moins de lookups upvalue

Bouger `type`, `pairs`, etc. en locals module-level (déjà fait dans
des bouts du codebase, pas uniformément). Économise un lookup de table
globale par dispatch sur PUC Lua.

---

Ces leviers sont **concrets, pas du handwaving**. Ensemble ils
fermeraient réalistiquement 30–50 % de l'écart résiduel avec le
dispatch natif sur PUC Lua, et effaceraient l'empreinte d'allocation
matcher+DSL sur les scenarios avec bindings. Ils ne sont
**volontairement pas dans v1.0** parce que :

- Les chiffres actuels sont déjà raisonnables pour les use cases visés
  (dispatch config-driven, unions discriminées, ergonomie à la Rust).
- La clarté du code compte plus pour un projet open-source jeune que
  les ns au pic. L'émission de source via `load()` est plus dure à
  débugguer, plus dure à stepper dedans, et plus dure à lire pour de
  nouveaux contributors.
- Optimiser sans feedback réel-monde, c'est le risque de chasser des
  benchmarks qui ne reflètent pas l'usage réel.

> [!TIP]
> **Si vous avez un use case réel où l'overhead de matchigo apparaît
> vraiment dans votre profiler — ouvrez une issue avec des métriques.**
> La roadmap d'optimisation au-dessus est sur la table s'il y a une
> preuve que ça aiderait quelqu'un. Une trace, un flamegraph, un "ce
> dispatcher est tout en haut de mon profile" — c'est ça qui fait
> basculer le coût/bénéfice. Les "rendez ça plus rapide" génériques
> recevront un poli "envoyez une PR" en retour.

---

## Reproduire en local

Depuis la racine du projet :

```sh
# Bench le runtime que vous avez
lua bench/run.lua             # full run, ~3 min — chiffres autoritatifs
lua bench/run.lua --fast      # smoke run, ~30 sec — vérif pipeline seulement

# Aggrège tout ce qu'il y a dans .stats/ vers matrix.md (pas de re-bench)
lua bench/matrix.lua

# Ou re-bench tous les runtimes détectés, puis render
lua bench/matrix.lua --all

# Ou re-bench des runtimes spécifiques uniquement
lua bench/matrix.lua 5.4=path/to/lua-5.4 luajit=path/to/luajit
```

Besoin d'installer le matrix de runtimes d'abord ? Voir
`scripts/install-lua.{ps1,sh}` — les deux construisent des trees Lua 5.1 /
5.2 / 5.3 / 5.4 / LuaJIT 2.1 self-contained sous `./.lua/` via
[hererocks](https://github.com/luarocks/hererocks).

---

> [!CAUTION]
> **Ne benchmarkez pas sur un runner CI partagé en faisant confiance aux
> chiffres ns absolus.** Les runners GitHub-hosted sont des VM mutualisées
> avec des voisins bruyants ; le même bench peut varier de 30 à 100 % entre
> deux runs. Le job CI smoke n'existe que pour vérifier que le bench script
> tourne proprement sur tous les runtimes. Les chiffres autoritatifs
> viennent de runs locaux sur du hardware stable.
