# Examples

Concrete use cases for matchigo-lua.

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

`compile` turns the rules into a hash-map fast path (the four literals collapse to `Map[v]` in O(1)).

## 2. Event dispatcher with destructuring

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

## 3. Validation pipeline with guards

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

A predicate (`isNum`) in the scope is the cleanest way to pair structural destructuring with type checks. You can also use `P.tuple` directly, but the DSL form keeps it readable.

## 5. Slice extraction (named rest)

```lua
local P = m.P

-- Array head + tail capture
local parseCmd = m.matcher({ Str = P.string })
    :with("['cd', target]",                  function(b) return { cmd = "cd", target = b.target } end)
    :with("['echo', ...words]",              function(b) return { cmd = "echo", words = b.words } end)
    :with("[head, ...tail] if head == 'rm'", function(b) return { cmd = "rm", files = b.tail } end)
    :otherwise(function() return nil end)

parseCmd({ "cd", "/home" })            --> { cmd = "cd", target = "/home" }
parseCmd({ "echo", "hello", "world" }) --> { cmd = "echo", words = { "hello", "world" } }
parseCmd({ "rm", "a.txt", "b.txt" })   --> { cmd = "rm", files = { "a.txt", "b.txt" } }

-- Shape rest capture
local routeBody = m.matcher()
    :with(m.parsePattern("{ kind: 'message', ...payload }"),
          function(b) return store(b.payload) end)
    :otherwise(function() return nil end)
```

## 6. Composing patterns built dynamically

```lua
-- Static pattern + runtime injection via $
local hotPaths = m.P.union("/health", "/metrics", "/ping")

local route = m.matcher({}, { hot = hotPaths })
    :with("$hot",         function(v) return cached_response(v) end)
    :with("'/api/users'", function() return list_users() end)
    :otherwise(           function(v) return not_found(v) end)
```

The `$hot` is resolved **at parse-time** to the injected pattern.

## 7. Dynamic matcher (rules added at runtime)

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

## 8. `isMatching` as a filter predicate

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

For a tight inner-loop filter, prefer compiling a one-rule matcher — `isMatching` rebuilds the test on each call for plain shapes, while `compile` caches it.

## 9. State machine (Rust-style)

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
        { otherwise = function() return state end }, -- unknown transition: no-op
    })
end

transition("idle", "start")    --> "running"
transition("running", "pause") --> "paused"
transition("paused", "reset")  --> "idle"
```

## 10. Native `if/elseif` vs matchigo — when to bother

```lua
-- Native — fastest on simple literal dispatch
local function classifyMethodNative(method)
    if     method == "GET"    then return list_handler
    elseif method == "POST"   then return create_handler
    elseif method == "PUT"    then return update_handler
    elseif method == "DELETE" then return delete_handler
    else                            return method_not_allowed
    end
end

-- matchigo — same runtime cost (literal hash O(1)), but composable + data-driven
local classifyMethod = m.compile({
    { with = "GET",    handler = function() return list_handler   end },
    { with = "POST",   handler = function() return create_handler end },
    { with = "PUT",    handler = function() return update_handler end },
    { with = "DELETE", handler = function() return delete_handler end },
    { otherwise = function() return method_not_allowed end },
})
```

For 4 literal branches: **stay native**. matchigo earns its keep when the branches involve shapes, guards, destructuring, or rules built at runtime — see examples 2–7 above.

---

## Game dev scenarios — when (not) to reach for matchigo

Game code has a particular shape : tight inner loops, event-driven dispatch,
state machines, composite entity queries. Each of these has its own verdict.

### A. Network packet / typed event dispatcher — matchigo wins on readability

A server (or client) receiving discriminated-union messages :

```lua
-- The contract : every packet has a `kind` field + variant-specific payload.
-- Native is fine for 3-4 cases ; once it grows past ~6 with guards, matchigo
-- stays flat where the if/elseif chain becomes a Christmas tree.

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

-- Single entry point for the network layer
function onPacket(p) handle(p) end
```

**Verdict** : here matchigo earns its dispatch cost. The grammar is
documenting itself, the guards stay inline, the fallback is explicit. With
6+ shapes and per-arm guards, the native form would be 30+ lines of nested
`if/elseif` that drifts from spec. **Use matchigo.**

### B. NPC AI state machine — perf loss for declarative gain

```lua
-- (state, perception) → next state. The full transition table is small and
-- closed (we know every state up front). Native is faster ; matchigo is
-- clearer when the transitions number 20+ and reviewers want to scan them
-- like a spec table.

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

**Verdict** : matchigo's tuple dispatch costs roughly an order of magnitude
more per transition than a hand-written `if/elseif` chain. **At 60 fps ×
many NPCs × multiple transitions per tick, this can become a measurable
slice of your frame budget.** Use matchigo here only if (a) your transition
table comes from data, or (b) the readability pays off and you're not
budget-constrained. Otherwise hand-roll the `if/elseif`.

### C. Composite entity query — native wins below 3 conditions, matchigo wins above

```lua
local entities = world.getAllEntities()  -- N entities

-- ❌ ANTI-PATTERN — single simple condition, matchigo adds overhead for nothing
local lowHp = {}
for _, e in ipairs(entities) do
    if m.isMatching(P.when(function(e) return e.hp < 50 end), e) then
        lowHp[#lowHp + 1] = e
    end
end

-- ✅ Correct form for the same intent
local lowHp = {}
for _, e in ipairs(entities) do
    if e.hp < 50 then lowHp[#lowHp + 1] = e end
end
```

```lua
-- ✅ Where matchigo earns its keep : composite, reusable, possibly data-driven
local scope = {
    isHostile = function(e) return e.faction ~= player.faction end,
    canSee    = function(e) return raycastVisible(player, e) end,
}

-- A reusable, named predicate stored in your AI module
local isThreat = m.parsePattern(
    "e if isHostile(e) and canSee(e) and e.hp > 0 and e.distance < 30",
    scope
)

local threats = {}
for _, e in ipairs(entities) do
    if m.isMatching(isThreat, e) then threats[#threats + 1] = e end
end
```

**Verdict** : if your filter is `e.hp < 50`, native wins on every axis. If
it's a 4-criterion composite that you reuse across modules and want to
serialize to config, matchigo's `parsePattern` becomes worth its overhead.
**Inflection point ≈ 3 conditions** — below, native is shorter and faster ;
above, matchigo readability dominates.

### D. Loot / damage classification — cardinal matters

```lua
-- Small cardinality (5 tiers) — native wins
local function rarityNative(value)
    if     value <  100  then return "common"
    elseif value <  500  then return "uncommon"
    elseif value < 2000  then return "rare"
    elseif value < 10000 then return "epic"
    else                      return "legendary"
    end
end

-- Large cardinality (50+ damage codes from your game design doc) — matchigo
-- wins because the if/elseif chain becomes O(n) sequential compares while
-- the literal hash dispatch stays O(1)
local damageType = m.compile({
    { with = "physical_blunt",  handler = function() return DMG.PHYSICAL end },
    { with = "physical_pierce", handler = function() return DMG.PHYSICAL end },
    { with = "physical_slash",  handler = function() return DMG.PHYSICAL end },
    { with = "fire_burn",       handler = function() return DMG.FIRE     end },
    { with = "fire_explosion",  handler = function() return DMG.FIRE     end },
    -- ... 45 more entries from the design spreadsheet
    { otherwise = function() return DMG.UNKNOWN end },
})
```

**Verdict** : at ~5 branches, native wins by a healthy margin (its
`if/elseif` chain stays cheap when most hits land early). At 50 branches,
matchigo's hash O(1) overtakes the chain — sequential string compares
add up. The crossover sits somewhere around **15-25 branches** depending
on hit distribution. If your damage type table is loaded from CSV/JSON
at boot, matchigo also lets you build the rules directly from the data —
no code change when the designers add a row.

### Bottom line for game dev

- **Hot inner loop, simple condition** (`e.hp < 50`, `flag == FLAG_X`) → native, always.
- **AI tick at 60 fps × many entities** → native unless your transition table is huge or data-driven.
- **Network event dispatcher with discriminated payloads** → matchigo, especially past 5 packet kinds.
- **Composite filter ≥ 3 criteria, reused** → matchigo. Below that, native.
- **Tag/ID classification ≥ ~20 keys** → matchigo's hash beats the chain.
- **Rules from designer config / CSV / JSON** → matchigo. Native can't express it without rolling its own dispatch table.

The honest take : matchigo is a **specific tool for specific shapes**. In a
typical game codebase you'll want it on a handful of files (event
dispatcher, packet handler, complex query module) and leave 95% of the
gameplay code alone with plain `if/elseif`.
