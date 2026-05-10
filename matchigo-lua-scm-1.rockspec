rockspec_format = "3.0"
package = "matchigo-lua"
version = "scm-1"

source = {
    url    = "git+https://github.com/SUP2Ak/matchigo-lua.git",
    branch = "main",
}

description = {
    summary  = "Pattern matching for Lua — composable P.* primitives, optional Rust-style DSL, compiled dispatcher.",
    detailed = [[
Development build (tracks main). For released versions, install matchigo-lua
without specifying scm-1.
]],
    homepage   = "https://github.com/SUP2Ak/matchigo-lua",
    license    = "MIT",
    maintainer = "SUP2Ak <cormier.wesley@gmail.com>",
    labels     = { "pattern-matching", "dsl", "dispatch", "match" },
    issues_url = "https://github.com/SUP2Ak/matchigo-lua/issues",
}

dependencies = {
    "lua >= 5.1",
}

build = {
    type = "builtin",
    modules = {
        ["matchigo"]                = "matchigo/init.lua",
        ["matchigo.match"]          = "matchigo/match.lua",
        ["matchigo.matcher"]        = "matchigo/matcher.lua",
        ["matchigo.compile"]        = "matchigo/compile.lua",
        ["matchigo.walk"]           = "matchigo/walk.lua",
        ["matchigo.p"]              = "matchigo/p.lua",
        ["matchigo.parsePattern"]   = "matchigo/parsePattern.lua",
        ["matchigo.types.bigint"]   = "matchigo/types/bigint.lua",
        ["matchigo.types.map"]      = "matchigo/types/map.lua",
        ["matchigo.types.set"]      = "matchigo/types/set.lua",
        ["matchigo.dsl.ast"]        = "matchigo/dsl/ast.lua",
        ["matchigo.dsl.lexer"]      = "matchigo/dsl/lexer.lua",
        ["matchigo.dsl.parser"]     = "matchigo/dsl/parser.lua",
        ["matchigo.dsl.eval"]       = "matchigo/dsl/eval.lua",
        ["matchigo.dsl.compile"]    = "matchigo/dsl/compile.lua",
        ["matchigo.util.compat"]    = "matchigo/util/compat.lua",
    },
    copy_directories = { "docs", "types" },
}

test = {
    type    = "command",
    command = "lua tests/run.lua",
}
