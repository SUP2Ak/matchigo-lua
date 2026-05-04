# Examples

Use-cases concrets pour matchigo-lua.

## 1. HTTP method router

```lua
local m = require("matchigo")

local route = m.compile({
    { with = "GET",    handler = function() return list_handler   end },
    { with = "POST",   handler = function() return create_handler end },
    { with = "PUT",    handler = function() return update_handler end },
    { with = "DELETE", handler = function() return delete_handler end },
    { otherwise = function() return method_not_allowed end },
})

local handler = route(request.method)
handler(request)
```

`compile` transforme les rules en hash-map fast-path (les 4 literals → `Map[v]` en O(1)).

## 2. Event dispatcher avec destructuring

```lua
local P = m.P

local handle = m.matcher({
    Str = P.string,
    Num = P.number,
    Click = { kind = "click" },
    Hover = { kind = "hover" },
})
    :with("Click & { x, y }",
          function(b) return ("click@%d,%d"):format(b.x, b.y) end)
    :with("Hover & { target: Str as id }",
          function(b) return "hover:" .. b.id end)
    :with("{ kind: 'scroll', delta: Num as d } if d > 0",
          function(b) return "scrollDown:" .. b.d end)
    :otherwise(function() return "ignore" end)

handle({ kind = "click", x = 10, y = 20 })       --> "click@10,20"
handle({ kind = "hover", target = "btn-1" })     --> "hover:btn-1"
handle({ kind = "scroll", delta = 5 })           --> "scrollDown:5"
handle({ kind = "scroll", delta = -3 })          --> "ignore" (guard fail)
```

## 3. Validation pipeline avec guards

```lua
local function isEmail(s) return type(s)=="string" and s:find("@",1,true) ~= nil end
local function isUrl(s)   return type(s)=="string" and s:match("^https?://") ~= nil end

local validate = m.matcher({
    Str = m.P.string,
    isEmail = isEmail,
    isUrl = isUrl,
})
    :with("s if isEmail(s)", function(b) return { kind = "email", value = b.s } end)
    :with("s if isUrl(s)",   function(b) return { kind = "url",   value = b.s } end)
    :with("Str",             function(v) return { kind = "text",  value = v } end)
    :otherwise(              function() return { kind = "invalid" } end)

validate("foo@bar.com")     --> { kind = "email", value = "foo@bar.com" }
validate("https://x.org")   --> { kind = "url",   value = "https://x.org" }
validate("plain text")      --> { kind = "text",  value = "plain text" }
validate(42)                --> { kind = "invalid" }
```

## 4. Tuple destructuring

```lua
local P = m.P

local scope = {
    Num   = P.number,
    isNum = function(v) return type(v) == "number" end,
}

local op = m.matcher(scope)
    :with("('add', a, b) if isNum(a) and isNum(b)", function(b) return b.a + b.b end)
    :with("('mul', a, b) if isNum(a) and isNum(b)", function(b) return b.a * b.b end)
    :with("('neg', x)    if isNum(x)",              function(b) return -b.x end)
    :otherwise(function() return nil, "unknown op" end)

op({ "add", 2, 3 })   --> 5
op({ "neg", 4 })      --> -4
op({ "div", 1, 0 })   --> nil, "unknown op"
```

Un prédicat (`isNum`) dans le scope est la façon la plus propre de combiner destructuring structurel et type-check. On peut aussi utiliser `P.tuple` directement, mais la forme DSL reste la plus lisible.

## 5. Slice extraction (named rest)

```lua
local P = m.P

-- Array head + tail capture
local parseCmd = m.matcher({ Str = P.string })
    :with("['cd', target]",                  function(b) return { cmd = "cd", target = b.target } end)
    :with("['echo', ...words]",              function(b) return { cmd = "echo", words = b.words } end)
    :with("[head, ...tail] if head == 'rm'", function(b) return { cmd = "rm", files = b.tail } end)
    :otherwise(function() return nil end)

parseCmd({ "cd", "/home" })           --> { cmd = "cd", target = "/home" }
parseCmd({ "echo", "hello", "world" }) --> { cmd = "echo", words = { "hello", "world" } }
parseCmd({ "rm", "a.txt", "b.txt" })  --> { cmd = "rm", files = { "a.txt", "b.txt" } }

-- Shape rest capture
local routeBody = m.matcher()
    :with(m.parsePattern("{ kind: 'message', ...payload }"),
          function(b) return store(b.payload) end)
    :otherwise(function() return nil end)
```

## 6. Composition de patterns construits dynamiquement

```lua
-- Pattern statique + injection runtime via $
local hotPaths = m.P.union("/health", "/metrics", "/ping")

local route = m.matcher({}, { hot = hotPaths })
    :with("$hot",         function(v) return cached_response(v) end)
    :with("'/api/users'", function() return list_users() end)
    :otherwise(           function(v) return not_found(v) end)
```

Le `$hot` est résolu **au parse-time** vers le pattern injecté.

## 7. Matcher dynamique (rules ajoutées en runtime)

```lua
local function buildHandlerFor(plugins)
    local builder = m.matcher({})
    for _, plugin in ipairs(plugins) do
        builder:with(plugin.pattern, plugin.handler)
    end
    return builder:otherwise(function() return default_handler() end)
end

-- Usage
local route = buildHandlerFor({
    { pattern = "'GET' & { path: '/x' }",  handler = handleX },
    { pattern = "'POST' & { path: '/y' }", handler = handleY },
})
```

## 8. `isMatching` comme prédicat de filtre

```lua
local adultPattern = { age = m.P.gte(18) }
local users = { { age = 12 }, { age = 22 }, { age = 30 } }

local adults = {}
for i = 1, #users do
    if m.isMatching(adultPattern, users[i]) then
        adults[#adults + 1] = users[i]
    end
end
```

Pour un filtre dans une boucle interne tendue, préférez compiler un matcher d'une seule rule — `isMatching` re-construit le test à chaque appel pour les shapes plain, alors que `compile` le cache.

## 9. Machine à états (style Rust)

```lua
local P = m.P

local function transition(state, event)
    return m.match({ state, event }, {
        { with = m.parsePattern("(_, 'reset')"),
          handler = function() return "idle" end },
        { with = m.parsePattern("('idle',     'start')"), handler = function() return "running"  end },
        { with = m.parsePattern("('running',  'pause')"), handler = function() return "paused"   end },
        { with = m.parsePattern("('paused',   'start')"), handler = function() return "running"  end },
        { with = m.parsePattern("('running',  'stop')"),  handler = function() return "stopped"  end },
        { otherwise = function() return state end }, -- transition inconnue : no-op
    })
end

transition("idle", "start")    --> "running"
transition("running", "pause") --> "paused"
transition("paused", "reset")  --> "idle"
```

## 10. Natif `if/elseif` vs matchigo — quand ça vaut le coup

```lua
-- Natif — plus rapide sur du dispatch littéral simple
local function classifyMethodNative(method)
    if     method == "GET"    then return list_handler
    elseif method == "POST"   then return create_handler
    elseif method == "PUT"    then return update_handler
    elseif method == "DELETE" then return delete_handler
    else                            return method_not_allowed
    end
end

-- matchigo — même coût runtime (hash O(1) sur littéraux), mais composable + data-driven
local classifyMethod = m.compile({
    { with = "GET",    handler = function() return list_handler   end },
    { with = "POST",   handler = function() return create_handler end },
    { with = "PUT",    handler = function() return update_handler end },
    { with = "DELETE", handler = function() return delete_handler end },
    { otherwise = function() return method_not_allowed end },
})
```

Pour 4 branches littérales : **restez natif**. matchigo gagne sa place quand les branches impliquent des shapes, des guards, du destructuring, ou des rules construites au runtime — voir exemples 2-7 plus haut.

---

## Game dev — quand (ne pas) sortir matchigo

Le code de jeu a une forme particulière : boucles internes tendues, dispatch
event-driven, machines à états, queries d'entités composites. Chaque cas a
son verdict propre.

### A. Dispatcher de paquets réseau / events typés — matchigo gagne sur la lisibilité

Un serveur (ou client) qui reçoit des messages à union discriminée :

```lua
-- Le contrat : chaque paquet a un champ `kind` + payload spécifique au variant.
-- Le natif reste OK pour 3-4 cas ; au-delà de ~6 avec des guards, matchigo
-- reste plat là où la chaîne if/elseif devient un sapin de Noël.

local handle = m.matcher({ Num = P.number, Str = P.string })
    :with("{ kind: 'move',     entityId: Num as id, x: Num as x, y: Num as y }",
          function(b) return moveEntity(b.id, b.x, b.y) end)
    :with("{ kind: 'attack',   entityId: Num as id, target: Num as t, dmg: Num as d } if d > 0",
          function(b) return resolveAttack(b.id, b.t, b.d) end)
    :with("{ kind: 'chat',     from: Num as id, text: Str as msg } if #msg > 0",
          function(b) return broadcastChat(b.id, b.msg) end)
    :with("{ kind: 'pickup',   entityId: Num as id, item: Str }",
          function(b) return tryPickup(b.id, b.item) end)
    :with("{ kind: 'use_item', entityId: Num as id, slot: Num as s }",
          function(b) return useItem(b.id, b.s) end)
    :otherwise(function(p) return logUnknownPacket(p) end)

-- Point d'entrée unique pour la couche réseau
function onPacket(p) handle(p) end
```

**Verdict** : ici matchigo mérite son coût de dispatch. La grammaire se
documente toute seule, les guards restent inline, le fallback est explicite.
Avec 6+ shapes et un guard ou deux par arm, la version native ferait 30+
lignes de `if/elseif` imbriqués qui dérivent peu à peu de la spec.
**Utilisez matchigo.**

### B. Machine à états IA d'un NPC — perte de perf pour gain déclaratif

```lua
-- (state, perception) → état suivant. La table de transitions complète est
-- petite et fermée (on connaît tous les états à l'avance). Le natif est plus
-- rapide ; matchigo est plus clair quand les transitions atteignent 20+
-- entrées et que les reviewers veulent les lire comme une table de spec.

local ai = m.compile({
    { with = m.parsePattern("(_, 'damaged') if hp < 0.2", { hp = npc.hp }),
      handler = function() return "flee" end },
    { with = m.parsePattern("('idle',       'sees_enemy')"),
      handler = function() return "alert" end },
    { with = m.parsePattern("('alert',      'sees_enemy_close')"),
      handler = function() return "attack" end },
    { with = m.parsePattern("('alert',      'lost_target')"),
      handler = function() return "patrol" end },
    { with = m.parsePattern("('attack',     'target_dead')"),
      handler = function() return "patrol" end },
    { with = m.parsePattern("('flee',       'safe')"),
      handler = function() return "idle" end },
    { otherwise = function(t) return t[1] end },
})

-- ai({ state, event }) → nextState
```

**Verdict** : le dispatch tuple matchigo coûte typiquement un ordre de
grandeur de plus par transition qu'une chaîne `if/elseif` écrite à la
main. **À 60 fps × beaucoup de NPCs × plusieurs transitions par tick,
ça peut devenir une part mesurable de votre budget frame.** Sortez
matchigo ici seulement si (a) la table de transitions vient de la
donnée, ou (b) la lisibilité paie et vous n'êtes pas budget-bound.
Sinon, écrivez le `if/elseif` à la main.

### C. Filtre composite d'entités — natif gagne sous 3 conditions, matchigo au-dessus

```lua
local entities = world.getAllEntities()  -- N entités

-- ❌ ANTI-PATTERN — condition simple unique, matchigo ajoute de l'overhead pour rien
local lowHp = {}
for _, e in ipairs(entities) do
    if m.isMatching(P.when(function(e) return e.hp < 50 end), e) then
        lowHp[#lowHp + 1] = e
    end
end

-- ✅ Forme correcte pour la même intention
local lowHp = {}
for _, e in ipairs(entities) do
    if e.hp < 50 then lowHp[#lowHp + 1] = e end
end
```

```lua
-- ✅ Là où matchigo gagne sa place : composite, réutilisable, possiblement data-driven
local scope = {
    isHostile = function(e) return e.faction ~= player.faction end,
    canSee    = function(e) return raycastVisible(player, e) end,
}

-- Un prédicat nommé, réutilisable, stocké dans votre module IA
local isThreat = m.parsePattern(
    "e if isHostile(e) and canSee(e) and e.hp > 0 and e.distance < 30",
    scope
)

local threats = {}
for _, e in ipairs(entities) do
    if m.isMatching(isThreat, e) then threats[#threats + 1] = e end
end
```

**Verdict** : si votre filtre c'est `e.hp < 50`, le natif gagne sur tous
les axes. Si c'est un composite à 4 critères que vous réutilisez à
travers plusieurs modules et voulez sérialiser en config, le
`parsePattern` de matchigo devient digne de son overhead.
**Point d'inflexion ≈ 3 conditions** — en-dessous, le natif est plus
court et plus rapide ; au-dessus, la lisibilité matchigo domine.

### D. Classification loot / dégâts — la cardinalité décide

```lua
-- Petite cardinalité (5 tiers) — natif gagne
local function rarityNative(value)
    if     value <  100  then return "common"
    elseif value <  500  then return "uncommon"
    elseif value < 2000  then return "rare"
    elseif value < 10000 then return "epic"
    else                      return "legendary"
    end
end

-- Grande cardinalité (50+ codes de dégâts depuis le game design doc) —
-- matchigo gagne parce que la chaîne if/elseif devient O(n) en
-- comparaisons séquentielles alors que le hash littéral reste O(1)
local damageType = m.compile({
    { with = "physical_blunt",  handler = function() return DMG.PHYSICAL end },
    { with = "physical_pierce", handler = function() return DMG.PHYSICAL end },
    { with = "physical_slash",  handler = function() return DMG.PHYSICAL end },
    { with = "fire_burn",       handler = function() return DMG.FIRE     end },
    { with = "fire_explosion",  handler = function() return DMG.FIRE     end },
    -- ... 45 entrées de plus venant du tableur de design
    { otherwise = function() return DMG.UNKNOWN end },
})
```

**Verdict** : à ~5 branches le natif gagne confortablement (sa chaîne
`if/elseif` reste cheap quand la plupart des hits tombent tôt). À 50
branches, le hash O(1) de matchigo dépasse la chaîne — les comparaisons
de strings séquentielles s'additionnent. Le crossover se situe quelque
part autour de **15-25 branches** selon la distribution des hits. Si
votre table de damage types est chargée depuis CSV/JSON au boot, matchigo
permet aussi de construire les rules directement depuis la donnée — pas
de change-code quand les designers ajoutent une ligne.

### Bilan game dev

- **Hot inner loop, condition simple** (`e.hp < 50`, `flag == FLAG_X`) → natif, toujours.
- **Tick IA à 60 fps × beaucoup d'entités** → natif sauf si la table de transitions est énorme ou data-driven.
- **Dispatcher d'events réseau avec payloads discriminés** → matchigo, surtout au-delà de 5 kinds de paquets.
- **Filtre composite ≥ 3 critères, réutilisé** → matchigo. En-dessous, natif.
- **Classification de tags/IDs ≥ ~20 clés** → le hash matchigo bat la chaîne.
- **Rules venant de la config designer / CSV / JSON** → matchigo. Le natif ne peut pas l'exprimer sans rouler sa propre table de dispatch.

Le verdict honnête : matchigo est un **outil spécifique pour des formes
spécifiques**. Dans une codebase de jeu typique vous voudrez l'utiliser
sur une poignée de fichiers (dispatcher d'events, handler de paquets,
module de query complexe) et laisser 95% du code gameplay tranquille
avec un `if/elseif` plain.
