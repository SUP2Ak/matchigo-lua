local p = require("matchigo.p")
local matchMod = require("matchigo.match")
local walkMod = require("matchigo.walk")
local matcherMod = require("matchigo.matcher")
local parsePatternMod = require("matchigo.parsePattern")
local BigInt = require("matchigo.types.bigint")
local Map = require("matchigo.types.map")
local Set = require("matchigo.types.set")

return {
    P = p.P,
    isP = p.isP,
    isSelect = p.isSelect,
    buildTest = p.buildTest,

    match = matchMod.match,
    compile = matchMod.compile,

    matcher = matcherMod.matcher,

    isMatching = walkMod.isMatching,

    parsePattern = parsePatternMod.parsePattern,

    BigInt = BigInt,
    Map = Map,
    Set = Set,
}
