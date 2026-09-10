var RITES = [
  {
    code: "ordinary",
    name: "Roman · Ordinary Form",
    short: "Ordinary",
    languages: [
      { code: "SP", name: "Español", rtl: false },
      { code: "AM", name: "English (US)", rtl: false },
      { code: "FR", name: "Français", rtl: false },
      { code: "IT", name: "Italiano", rtl: false },
      { code: "DE", name: "Deutsch", rtl: false },
      { code: "PT", name: "Português", rtl: false },
      { code: "AR", name: "العربية", rtl: true },
      { code: "PL", name: "Polski", rtl: false },
      { code: "NL", name: "Nederlands", rtl: false },
      { code: "GR", name: "Ελληνικά", rtl: false },
      { code: "MG", name: "Malagasy", rtl: false }
    ]
  },
  {
    code: "extraordinary",
    name: "Roman · 1962 Missal",
    short: "1962 Missal",
    languages: [
      { code: "TRA", name: "English (US)", rtl: false },
      { code: "TRS", name: "Español", rtl: false },
      { code: "TRF", name: "Français", rtl: false },
      { code: "TRD", name: "Deutsch", rtl: false }
    ]
  },
  { code: "armenian", name: "Armenian Rite", short: "Armenian", languages: [{ code: "ARM", name: "Հայերեն", rtl: false }] },
  { code: "byzantine", name: "Byzantine Rite", short: "Byzantine", languages: [{ code: "BYA", name: "العربية", rtl: true }] },
  { code: "coptic", name: "Coptic Rite", short: "Coptic", languages: [{ code: "COA", name: "العربية", rtl: true }] },
  { code: "maronite", name: "Maronite Rite", short: "Maronite", languages: [{ code: "MAA", name: "العربية", rtl: true }] },
  { code: "syriac", name: "Syriac Rite", short: "Syriac", languages: [{ code: "SYA", name: "العربية", rtl: true }] }
]

var LANGUAGES = []
for (var _r = 0; _r < RITES.length; _r++)
  for (var _l = 0; _l < RITES[_r].languages.length; _l++)
    LANGUAGES.push(RITES[_r].languages[_l])

function languageList() {
  return LANGUAGES.slice()
}

function riteList() {
  return RITES.slice()
}

function normalizeRite(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "").toLowerCase()
  for (var i = 0; i < RITES.length; i++)
    if (RITES[i].code === text) return RITES[i].code
  return ""
}

function riteEntry(value) {
  var code = normalizeRite(value)
  for (var i = 0; i < RITES.length; i++)
    if (RITES[i].code === code) return RITES[i]
  return RITES[0]
}

function riteForLanguage(value) {
  var code = normalizeLanguage(value)
  for (var i = 0; i < RITES.length; i++)
    for (var j = 0; j < RITES[i].languages.length; j++)
      if (RITES[i].languages[j].code === code) return RITES[i]
  return RITES[0]
}

function riteIndex(value) {
  var code = normalizeRite(value)
  for (var i = 0; i < RITES.length; i++)
    if (RITES[i].code === code) return i
  return 0
}

function languagesForRite(value) {
  return riteEntry(value).languages.slice()
}

function languageIndexInRite(riteCode, langCode) {
  var langs = riteEntry(riteCode).languages
  var code = normalizeLanguage(langCode)
  var name = languageLabel(code)
  for (var i = 0; i < langs.length; i++)
    if (langs[i].code === code) return i
  if (name !== "")
    for (var j = 0; j < langs.length; j++)
      if (langs[j].name === name) return j
  return 0
}

function matchLanguageInRite(riteCode, langCode) {
  var langs = riteEntry(riteCode).languages
  var code = normalizeLanguage(langCode)
  var name = languageLabel(code)
  for (var i = 0; i < langs.length; i++)
    if (langs[i].code === code) return langs[i].code
  if (name !== "")
    for (var j = 0; j < langs.length; j++)
      if (langs[j].name === name) return langs[j].code
  return ""
}

function normalizeLanguage(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "").toUpperCase()
  if (text === "") return ""
  for (var i = 0; i < LANGUAGES.length; i++)
    if (LANGUAGES[i].code === text) return LANGUAGES[i].code
  return ""
}

function languageEntry(value) {
  var code = normalizeLanguage(value)
  if (code === "") return null
  for (var i = 0; i < LANGUAGES.length; i++)
    if (LANGUAGES[i].code === code) return LANGUAGES[i]
  return null
}

function languageLabel(value) {
  var entry = languageEntry(value)
  return entry ? entry.name : ""
}

function isRtlLanguage(value) {
  var entry = languageEntry(value)
  return !!(entry && entry.rtl)
}

function languageIndex(value) {
  var code = normalizeLanguage(value)
  if (code === "") return 0
  for (var i = 0; i < LANGUAGES.length; i++)
    if (LANGUAGES[i].code === code) return i
  return 0
}

var TABS = ["readings", "gospel", "commentary"]
var MAX_LOOKBACK_DAYS = 30

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function isoDate(date) {
  if (!date || typeof date.getFullYear !== "function") return ""
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function startOfDay(date) {
  if (!date || typeof date.getFullYear !== "function") return new Date()
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date, delta) {
  var next = startOfDay(date)
  next.setDate(next.getDate() + Number(delta || 0))
  return next
}

function clampViewDate(date, today) {
  var now = startOfDay(today || new Date())
  var day = startOfDay(date || now)
  var earliest = addDays(now, -MAX_LOOKBACK_DAYS)
  if (day.getTime() > now.getTime()) return now
  if (day.getTime() < earliest.getTime()) return earliest
  return day
}

function isSameDay(a, b) {
  return isoDate(a) !== "" && isoDate(a) === isoDate(b)
}

function canStepDate(date, today, delta) {
  var current = clampViewDate(date, today)
  var stepped = addDays(current, delta)
  var clamped = clampViewDate(stepped, today)
  return isoDate(clamped) === isoDate(stepped)
}

function emptyReading(kind) {
  return { kind: kind || "", title: "", reference: "", text: "" }
}

function emptyCommentary() {
  return { available: false, title: "", author: "", source: "", text: "" }
}

function emptyDay() {
  return {
    date: "",
    language: "",
    liturgicalTitle: "",
    saint: "",
    readings: [],
    gospel: emptyReading("gospel"),
    commentary: emptyCommentary(),
    provider: "",
    fetchedAt: ""
  }
}

function asText(value) {
  return String(value === undefined || value === null ? "" : value)
}

function normalizeReading(raw, fallbackKind) {
  var item = raw && typeof raw === "object" ? raw : {}
  return {
    kind: asText(item.kind || fallbackKind),
    title: asText(item.title),
    reference: asText(item.reference),
    text: asText(item.text)
  }
}

function normalizeCommentary(raw) {
  var item = raw && typeof raw === "object" ? raw : {}
  var text = asText(item.text)
  return {
    available: item.available === true || text !== "",
    title: asText(item.title),
    author: asText(item.author),
    source: asText(item.source),
    text: text
  }
}

function parsePayload(raw) {
  var data = raw
  if (typeof raw === "string") {
    var text = raw.replace(/^\s+|\s+$/g, "")
    if (text === "") return null
    try {
      data = JSON.parse(text)
    } catch (e) {
      return null
    }
  }
  if (!data || typeof data !== "object") return null
  var readings = []
  var sourceReadings = data.readings
  if (sourceReadings && typeof sourceReadings.length === "number") {
    for (var i = 0; i < sourceReadings.length; i++) {
      var reading = normalizeReading(sourceReadings[i], "")
      if (reading.text !== "") readings.push(reading)
    }
  }
  return {
    date: asText(data.date),
    language: normalizeLanguage(data.language),
    liturgicalTitle: asText(data.liturgicalTitle),
    saint: asText(data.saint),
    readings: readings,
    gospel: normalizeReading(data.gospel, "gospel"),
    commentary: normalizeCommentary(data.commentary),
    provider: asText(data.provider) || "evangelizo.org",
    fetchedAt: asText(data.fetchedAt)
  }
}

function tabId(index) {
  var n = Number(index)
  if (!isFinite(n) || n < 0 || n > 2) return TABS[0]
  return TABS[n]
}

function commentaryByline(commentary) {
  var item = commentary && typeof commentary === "object" ? commentary : {}
  var author = asText(item.author)
  var source = asText(item.source)
  if (author !== "" && source !== "") return author + " · " + source
  return author || source
}

function formatReading(entry) {
  var item = entry && typeof entry === "object" ? entry : {}
  var parts = []
  var title = asText(item.title)
  var reference = asText(item.reference)
  var text = asText(item.text)
  if (title !== "") parts.push(title)
  if (reference !== "" && reference !== title) parts.push(reference)
  if (text !== "") parts.push(text)
  return parts.join("\n")
}

function copyText(day, tabIndex) {
  if (!day || typeof day !== "object") return ""
  var blocks = []
  var title = asText(day.liturgicalTitle)
  var saint = asText(day.saint)
  if (title !== "") blocks.push(title)
  if (saint !== "") blocks.push(saint)
  var n = Number(tabIndex)
  if (n === 0) {
    var readings = day.readings
    if (readings && typeof readings.length === "number") {
      for (var i = 0; i < readings.length; i++) {
        var block = formatReading(readings[i])
        if (block !== "") blocks.push(block)
      }
    }
  } else if (n === 2) {
    var commentary = normalizeCommentary(day.commentary)
    var note = []
    var byline = commentaryByline(commentary)
    if (commentary.title !== "") note.push(commentary.title)
    if (byline !== "") note.push(byline)
    if (commentary.text !== "") note.push(commentary.text)
    if (note.length > 0) blocks.push(note.join("\n"))
  } else {
    var gospel = formatReading(day.gospel)
    if (gospel !== "") blocks.push(gospel)
  }
  return blocks.join("\n\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    LANGUAGES: LANGUAGES,
    RITES: RITES,
    TABS: TABS,
    languageList: languageList,
    riteList: riteList,
    normalizeRite: normalizeRite,
    riteEntry: riteEntry,
    riteForLanguage: riteForLanguage,
    riteIndex: riteIndex,
    languagesForRite: languagesForRite,
    languageIndexInRite: languageIndexInRite,
    matchLanguageInRite: matchLanguageInRite,
    normalizeLanguage: normalizeLanguage,
    languageEntry: languageEntry,
    languageLabel: languageLabel,
    isRtlLanguage: isRtlLanguage,
    languageIndex: languageIndex,
    emptyDay: emptyDay,
    parsePayload: parsePayload,
    tabId: tabId,
    commentaryByline: commentaryByline,
    formatReading: formatReading,
    copyText: copyText,
    MAX_LOOKBACK_DAYS: MAX_LOOKBACK_DAYS,
    isoDate: isoDate,
    addDays: addDays,
    clampViewDate: clampViewDate,
    isSameDay: isSameDay,
    canStepDate: canStepDate
  }
}
