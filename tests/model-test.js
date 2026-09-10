const assert = require("assert")
const Model = require("../Model.js")

assert.strictEqual(Model.normalizeLanguage(""), "")
assert.strictEqual(Model.normalizeLanguage(null), "")
assert.strictEqual(Model.normalizeLanguage("sp"), "SP")
assert.strictEqual(Model.normalizeLanguage(" AM "), "AM")
assert.strictEqual(Model.normalizeLanguage("xx"), "")
assert.strictEqual(Model.normalizeLanguage("TRA"), "TRA")
assert.strictEqual(Model.normalizeLanguage("tra"), "TRA")
assert.strictEqual(Model.normalizeLanguage("maa"), "MAA")
assert.strictEqual(Model.languageLabel("AR"), "العربية")
assert.strictEqual(Model.isRtlLanguage("AR"), true)
assert.strictEqual(Model.isRtlLanguage("ar"), true)
assert.strictEqual(Model.isRtlLanguage("SP"), false)
assert.strictEqual(Model.isRtlLanguage("GR"), false)
assert.strictEqual(Model.languageEntry("AR").rtl, true)
assert.deepStrictEqual(Model.languageList().map((item) => item.code), [
  "SP", "AM", "FR", "IT", "DE", "PT", "AR", "PL", "NL", "GR", "MG",
  "TRA", "TRS", "TRF", "TRD",
  "ARM", "BYA", "COA", "MAA", "SYA"
])
assert.strictEqual(Model.languageList().length, 20)
assert.strictEqual(Model.languageIndex("DE"), 4)
assert.strictEqual(Model.languageIndex(""), 0)

assert.deepStrictEqual(Model.riteList().map((item) => item.code), [
  "ordinary", "extraordinary", "armenian", "byzantine", "coptic", "maronite", "syriac"
])
assert.strictEqual(Model.normalizeRite("Extraordinary"), "extraordinary")
assert.strictEqual(Model.normalizeRite("xx"), "")
assert.strictEqual(Model.riteEntry("maronite").languages[0].code, "MAA")
assert.strictEqual(Model.riteEntry("").code, "ordinary")
assert.strictEqual(Model.riteForLanguage("AM").code, "ordinary")
assert.strictEqual(Model.riteForLanguage("TRF").code, "extraordinary")
assert.strictEqual(Model.riteForLanguage("SYA").code, "syriac")
assert.strictEqual(Model.riteForLanguage("").code, "ordinary")
assert.strictEqual(Model.riteIndex("extraordinary"), 1)
assert.strictEqual(Model.languagesForRite("extraordinary").length, 4)
assert.strictEqual(Model.languageIndexInRite("extraordinary", "AM"), 0)
assert.strictEqual(Model.languageIndexInRite("extraordinary", "FR"), 2)
assert.strictEqual(Model.matchLanguageInRite("extraordinary", "AM"), "TRA")
assert.strictEqual(Model.matchLanguageInRite("extraordinary", "TRD"), "TRD")
assert.strictEqual(Model.matchLanguageInRite("ordinary", "TRS"), "SP")
assert.strictEqual(Model.matchLanguageInRite("extraordinary", "PL"), "")
assert.strictEqual(Model.matchLanguageInRite("extraordinary", ""), "")
assert.strictEqual(Model.isRtlLanguage("MAA"), true)
assert.strictEqual(Model.isRtlLanguage("TRA"), false)

const parsed = Model.parsePayload(JSON.stringify({
  date: "2026-08-15",
  language: "sp",
  liturgicalTitle: "Prueba",
  saint: "Santa Prueba",
  readings: [{ kind: "first", title: "T", reference: "R", text: "Texto" }, { kind: "second", title: "", reference: "", text: "" }],
  gospel: { kind: "gospel", title: "G", reference: "Ev", text: "Evangelio" },
  commentary: { available: true, title: "C", author: "A", source: "S", text: "Nota" },
  provider: "evangelizo.org",
  fetchedAt: "2026-08-15T00:00:00+00:00"
}))
assert.strictEqual(parsed.language, "SP")
assert.strictEqual(parsed.saint, "Santa Prueba")
assert.strictEqual(parsed.readings.length, 1)
assert.strictEqual(parsed.gospel.text, "Evangelio")
assert.strictEqual(parsed.commentary.author, "A")
assert.strictEqual(Model.copyText(parsed, 0), "Prueba\n\nSanta Prueba\n\nT\nR\nTexto")
assert.strictEqual(Model.copyText(parsed, 1), "Prueba\n\nSanta Prueba\n\nG\nEv\nEvangelio")
assert.strictEqual(Model.copyText(parsed, 2), "Prueba\n\nSanta Prueba\n\nC\nA · S\nNota")
assert.strictEqual(Model.copyText(null, 1), "")
assert.strictEqual(Model.parsePayload(""), null)
assert.strictEqual(Model.parsePayload("{"), null)
assert.strictEqual(Model.tabId(1), "gospel")

const today = new Date(2026, 7, 15)
assert.strictEqual(Model.isoDate(today), "2026-08-15")
assert.strictEqual(Model.isoDate(Model.addDays(today, -1)), "2026-08-14")
assert.strictEqual(Model.canStepDate(today, today, 1), false)
assert.strictEqual(Model.canStepDate(today, today, -1), true)
assert.strictEqual(Model.isoDate(Model.clampViewDate(Model.addDays(today, -40), today)), "2026-07-16")
assert.strictEqual(Model.isSameDay(today, new Date(2026, 7, 15)), true)

console.log("model-test: ok")
