# shellcheck shell=bash
# Sonarr's and Radarr's quality settings: the kit's defaults (custom formats, quality profiles,
# quality sizes and, for Sonarr, release profiles) and the code that puts them in an app through
# its API, into an app that still has its stock settings. Sourced by the media stack's wire hook
# (a file of hooks/ that isn't a step of its own), which has lib/api.sh's api_call and the kit's
# ok and warn. Profiles name their custom formats (formatScores) rather than giving ids, since
# ids differ per app; a quality the app doesn't know is left out, and one the defaults don't name
# is added as not allowed. Checked against Sonarr 4.0 and Radarr 6.

# The kit's defaults, one app's per heredoc. The profiles keep the stock ones' names (Any, SD,
# HD-720p, ...), with upgrades in Any up to 1080p and 720p/1080p WEB and Bluray as one tier;
# Sonarr prefers season packs and adds profiles of its own, each with HDTV, WEB and Bluray as one
# tier per resolution (Anime's SD tier is DVD and 480p WEB; Anime (No Upgrades) is Anime without
# upgrades). Anime wants Japanese audio with English soft subs: dubs-only, raw and
# non-English-sub releases turned away, trusted English sub groups preferred (keep the two
# Non-English formats apart: a format with both Language and Release Title conditions needs one
# of each to match). TV Animation and TV Live Action prefer x265, turn away MULTi/French releases
# and single episodes over 0.6 GB or 2.5 GB; a size condition sees a season pack's whole size, so
# packs are left to the quality sizes. Radarr prefers x265 in every profile (+25) but still takes
# x264 (no minimum or cutoff format score, so an x264 file isn't upgraded just for that), and its
# sizes hold a 2-hour 1080p film to about 3.4 GB preferred and 7 GB at most.
# removeProfiles are stock profiles the defaults drop (nothing uses them yet in a stock app).
arrq_data() {       # app -> its defaults (JSON)
    case "$1" in
        sonarr) cat <<'JSON'
{"customFormats":[
{"name":"Dubs Only","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"Dubbed","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"^(?!.*(Dual|Multi)[-_. ]?Audio).*((?<!multi-)\\b(dub(bed)?)\\b|(funi|eng(lish)?)_?dub)"}]},{"name":"Golumpa","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(Golumpa)\\b"}]},{"name":"KaiDubs (Not Dual Audio)","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"^(?!.*(dual[ ._-]?audio|[([]dual[])]|(JA|ZH|KO)\\+EN|EN\\+(JA|ZH|KO))).*\\b(KaiDubs)\\b"}]},{"name":"KamiFS","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(KamiFS)\\b"}]},{"name":"KS (Not Dual Audio)","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"^(?!.*(dual[ ._-]?audio|[([]dual[])]|(JA|ZH|KO)\\+EN|EN\\+(JA|ZH|KO))).*\\bKS\\b"}]},{"name":"torenter69","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(torenter69)\\b"}]},{"name":"Yameii","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\[Yameii\\]|-Yameii\\b"}]}]},
{"name":"Anime Raws","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"AsukaRaws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Asuka[ ._-]?(Raws)"}]},{"name":"Beatrice-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Beatrice[ ._-]?(Raws)"}]},{"name":"Daddy-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Daddy[ ._-]?(Raws)"}]},{"name":"Fumi-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Fumi[ ._-]?(Raws)"}]},{"name":"IrizaRaws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Iriza[ ._-]?(Raws)"}]},{"name":"Kawaiika-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Kawaiika[ ._-]?(Raws)"}]},{"name":"km","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\[km\\]|-km\\b"}]},{"name":"Koi-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Koi[ ._-]?(Raws)"}]},{"name":"Lilith-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Lilith[ ._-]?(Raws)"}]},{"name":"LowPower-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"LowPower[ ._-]?(Raws)"}]},{"name":"Moozzi2","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(Moozzi2)\\b"}]},{"name":"NanakoRaws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Nanako[ ._-]?(Raws)"}]},{"name":"NC-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"NC[ ._-]?(Raws)"}]},{"name":"neko-raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"neko[ ._-]?(raws)"}]},{"name":"New-raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"New[ ._-]?(raws)"}]},{"name":"Ohys-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Ohys[ ._-]?(Raws)"}]},{"name":"Pandoratv-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Pandoratv[ ._-]?(Raws)"}]},{"name":"Raws-Maji","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(Raws-Maji)\\b"}]},{"name":"ReinForce","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(ReinForce)\\b"}]},{"name":"Scryous-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Scryous[ ._-]?(Raws)"}]},{"name":"Seicher-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Seicher[ ._-]?(Raws)"}]},{"name":"Shiniori-Raws","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"Shiniori[ ._-]?(Raws)"}]}]},
{"name":"Season Pack","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"Season Pack","implementation":"ReleaseTypeSpecification","negate":false,"required":false,"fields":[{"name":"value","value":3}]}]},
{"name":"Non-English Subs (Title)","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"Non-English sub markers","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"简|繁|内封|内嵌|字幕|VietSub|ซับ|Naruto-Kun\\.Hu|\\b(CHS|CHT|hardsubs?|VOSTFR|Legendado)\\b"}]},{"name":"Spanish/Portuguese-only releases","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"^(?!.*\\bMulti).*\\b(ESP|Spanish|Español|Castellano|Latino|PT-?BR)\\b"}]}]},
{"name":"English Sub Groups","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"Trusted English sub groups","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(SubsPlease|Erai-raws|HorribleSubs|EMBER|Judas|ASW|Commie|GJM|Kametsu|MTBB|Okay-Subs|LostYears|Trix|CBM|BlueLobster|Anime Time)\\b"}]}]},
{"name":"Non-English Subs (Language)","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"Chinese","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":10},{"name":"exceptLanguage","value":false}]},{"name":"Vietnamese","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":13},{"name":"exceptLanguage","value":false}]},{"name":"Hungarian","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":22},{"name":"exceptLanguage","value":false}]},{"name":"Thai","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":32},{"name":"exceptLanguage","value":false}]},{"name":"Spanish","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":3},{"name":"exceptLanguage","value":false}]},{"name":"Spanish (Latino)","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":34},{"name":"exceptLanguage","value":false}]},{"name":"Portuguese (Brazil)","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":33},{"name":"exceptLanguage","value":false}]},{"name":"French","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":2},{"name":"exceptLanguage","value":false}]},{"name":"German","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":4},{"name":"exceptLanguage","value":false}]},{"name":"Italian","implementation":"LanguageSpecification","negate":false,"required":false,"fields":[{"name":"value","value":5},{"name":"exceptLanguage","value":false}]}]},
{"name":"x265 / HEVC","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"x265","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(x265|HEVC|[hH][ .]?265)\\b"}]}]},
{"name":"MULTi / French Audio","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"MULTi/French","implementation":"ReleaseTitleSpecification","negate":false,"required":false,"fields":[{"name":"value","value":"\\b(MULTi|TRUEFRENCH|FRENCH|VFF|VFQ|VF2)\\b"}]}]},
{"name":"Oversize (Animation)","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"over 0.6 GB","implementation":"SizeSpecification","negate":false,"required":true,"fields":[{"name":"min","value":0.6},{"name":"max","value":1000}]},{"name":"Not a season pack","implementation":"ReleaseTypeSpecification","negate":true,"required":true,"fields":[{"name":"value","value":3}]}]},
{"name":"Oversize (Live Action)","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"over 2.5 GB","implementation":"SizeSpecification","negate":false,"required":true,"fields":[{"name":"min","value":2.5},{"name":"max","value":1000}]},{"name":"Not a season pack","implementation":"ReleaseTypeSpecification","negate":true,"required":true,"fields":[{"name":"value","value":3}]}]}
],"qualityProfiles":[
{"name":"Any","upgradeAllowed":true,"cutoff":1002,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Season Pack":10,"Anime Raws":-10000,"Dubs Only":-10000},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"id":1000,"name":"WEB 480p","allowed":true,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true}]},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":true},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"id":1001,"name":"720p","allowed":true,"items":[{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true}]},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"id":1002,"name":"1080p","allowed":true,"items":[{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true}]},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"SD","upgradeAllowed":false,"cutoff":1,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"id":1000,"name":"WEB 480p","allowed":true,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true}]},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":true},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":false},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"id":1001,"name":"WEB 720p","allowed":false,"items":[{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":false},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":false}]},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":false},{"id":1002,"name":"WEB 1080p","allowed":false,"items":[{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":false},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":false}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"HD-720p","upgradeAllowed":false,"cutoff":4,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Season Pack":10},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false}]},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":false},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"id":1001,"name":"WEB 720p","allowed":true,"items":[{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true}]},{"id":1002,"name":"WEB 1080p","allowed":false,"items":[{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":false},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":false}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"HD-1080p","upgradeAllowed":false,"cutoff":9,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Season Pack":10},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false}]},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":false},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":false},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"id":1001,"name":"WEB 720p","allowed":false,"items":[{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":false},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":false}]},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":false},{"id":1002,"name":"WEB 1080p","allowed":true,"items":[{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"Ultra-HD","upgradeAllowed":false,"cutoff":16,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false}]},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":false},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":false},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"id":1001,"name":"WEB 720p","allowed":false,"items":[{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":false},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":false}]},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":false},{"id":1002,"name":"WEB 1080p","allowed":false,"items":[{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":false},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":false}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":true},{"id":1003,"name":"WEB 2160p","allowed":true,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":true},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":true}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":true},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"HD - 720p/1080p","upgradeAllowed":false,"cutoff":4,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Season Pack":10},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false}]},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true},{"id":1002,"name":"WEB 1080p","allowed":true,"items":[{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true}]},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true},{"id":1001,"name":"WEB 720p","allowed":true,"items":[{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true}]},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"Anime","upgradeAllowed":true,"cutoff":1002,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Anime Raws":-10000,"Dubs Only":-10000,"Non-English Subs (Title)":-10000,"Non-English Subs (Language)":-10000,"English Sub Groups":100},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"id":1000,"name":"SD (DVD/WEB 480p)","allowed":true,"items":[{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true}]},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":true},{"id":1001,"name":"720p","allowed":true,"items":[{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true}]},{"id":1002,"name":"1080p","allowed":true,"items":[{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true}]},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"Anime (No Upgrades)","upgradeAllowed":false,"cutoff":1002,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Anime Raws":-10000,"Dubs Only":-10000,"Non-English Subs (Title)":-10000,"Non-English Subs (Language)":-10000,"English Sub Groups":100},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"id":1000,"name":"SD (DVD/WEB 480p)","allowed":true,"items":[{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true}]},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":true},{"id":1001,"name":"720p","allowed":true,"items":[{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true}]},{"id":1002,"name":"1080p","allowed":true,"items":[{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true}]},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"TV Animation","upgradeAllowed":true,"cutoff":1002,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Season Pack":10,"Anime Raws":-10000,"Dubs Only":-10000,"x265 / HEVC":25,"MULTi / French Audio":-10000,"Oversize (Animation)":-10000},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"id":1000,"name":"WEB 480p","allowed":true,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true}]},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":true},{"id":1001,"name":"720p","allowed":true,"items":[{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true}]},{"id":1002,"name":"1080p","allowed":true,"items":[{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true}]},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]},
{"name":"TV Live Action","upgradeAllowed":true,"cutoff":1002,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"formatScores":{"Season Pack":10,"Anime Raws":-10000,"Dubs Only":-10000,"x265 / HEVC":25,"MULTi / French Audio":-10000,"Oversize (Live Action)":-10000},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false},{"quality":{"id":20,"name":"Bluray-1080p Remux"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"id":1000,"name":"WEB 480p","allowed":true,"items":[{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true},{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true}]},{"quality":{"id":13,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":22,"name":"Bluray-576p"},"items":[],"allowed":true},{"id":1001,"name":"720p","allowed":true,"items":[{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true}]},{"id":1002,"name":"1080p","allowed":true,"items":[{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true}]},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false},{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-2160p Remux"},"items":[],"allowed":false}]}
],"removeProfiles":[],"qualityDefinitions":[
{"quality":"Unknown","minSize":1,"maxSize":199.9,"preferredSize":95},
{"quality":"SDTV","minSize":2,"maxSize":100,"preferredSize":95},
{"quality":"WEBRip-480p","minSize":2,"maxSize":100,"preferredSize":95},
{"quality":"WEBDL-480p","minSize":2,"maxSize":100,"preferredSize":95},
{"quality":"DVD","minSize":2,"maxSize":100,"preferredSize":95},
{"quality":"Bluray-480p","minSize":2,"maxSize":100,"preferredSize":95},
{"quality":"Bluray-576p","minSize":2,"maxSize":100,"preferredSize":95},
{"quality":"HDTV-720p","minSize":3,"maxSize":125,"preferredSize":95},
{"quality":"HDTV-1080p","minSize":4,"maxSize":125,"preferredSize":95},
{"quality":"Raw-HD","minSize":4,"maxSize":null,"preferredSize":95},
{"quality":"WEBRip-720p","minSize":3,"maxSize":130,"preferredSize":95},
{"quality":"WEBDL-720p","minSize":3,"maxSize":130,"preferredSize":95},
{"quality":"Bluray-720p","minSize":4,"maxSize":130,"preferredSize":95},
{"quality":"WEBRip-1080p","minSize":4,"maxSize":130,"preferredSize":95},
{"quality":"WEBDL-1080p","minSize":4,"maxSize":130,"preferredSize":95},
{"quality":"Bluray-1080p","minSize":4,"maxSize":129.5,"preferredSize":95},
{"quality":"Bluray-1080p Remux","minSize":34.9,"maxSize":130.5,"preferredSize":95},
{"quality":"HDTV-2160p","minSize":35,"maxSize":199.9,"preferredSize":95},
{"quality":"WEBRip-2160p","minSize":35,"maxSize":null,"preferredSize":95},
{"quality":"WEBDL-2160p","minSize":35,"maxSize":null,"preferredSize":95},
{"quality":"Bluray-2160p","minSize":35,"maxSize":null,"preferredSize":95},
{"quality":"Bluray-2160p Remux","minSize":35,"maxSize":null,"preferredSize":95}
],"releaseProfiles":[

]}
JSON
            ;;
        radarr) cat <<'JSON'
{"customFormats":[
{"name":"x265 / HEVC","includeCustomFormatWhenRenaming":false,"specifications":[{"name":"x265","implementation":"ReleaseTitleSpecification","negate":false,"required":true,"fields":[{"name":"value","value":"\\b(x265|HEVC|h\\.?265)\\b"}]}]}
],"qualityProfiles":[
{"name":"Any","upgradeAllowed":true,"cutoff":1004,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"language":{"id":-2,"name":"Original"},"formatScores":{"x265 / HEVC":25},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":24,"name":"WORKPRINT"},"items":[],"allowed":false},{"quality":{"id":25,"name":"CAM"},"items":[],"allowed":false},{"quality":{"id":26,"name":"TELESYNC"},"items":[],"allowed":false},{"quality":{"id":27,"name":"TELECINE"},"items":[],"allowed":false},{"quality":{"id":29,"name":"REGIONAL"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false},{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false}]},{"quality":{"id":31,"name":"Remux-2160p"},"items":[],"allowed":false},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":30,"name":"Remux-1080p"},"items":[],"allowed":false},{"quality":{"id":23,"name":"DVD-R"},"items":[],"allowed":false},{"quality":{"id":28,"name":"DVDSCR"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"id":1000,"name":"WEB 480p","allowed":true,"items":[{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true}]},{"quality":{"id":20,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":21,"name":"Bluray-576p"},"items":[],"allowed":true},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"id":1001,"name":"720p","allowed":true,"items":[{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true}]},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"id":1004,"name":"1080p","allowed":true,"items":[{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true}]},{"quality":{"id":22,"name":"BR-DISK"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false}]},
{"name":"SD","upgradeAllowed":false,"cutoff":20,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"language":{"id":-2,"name":"Original"},"formatScores":{"x265 / HEVC":25},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":24,"name":"WORKPRINT"},"items":[],"allowed":true},{"quality":{"id":25,"name":"CAM"},"items":[],"allowed":true},{"quality":{"id":26,"name":"TELESYNC"},"items":[],"allowed":true},{"quality":{"id":27,"name":"TELECINE"},"items":[],"allowed":true},{"quality":{"id":29,"name":"REGIONAL"},"items":[],"allowed":true},{"quality":{"id":28,"name":"DVDSCR"},"items":[],"allowed":true},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":true},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":true},{"quality":{"id":23,"name":"DVD-R"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":true,"items":[{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":true},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":true}]},{"quality":{"id":20,"name":"Bluray-480p"},"items":[],"allowed":true},{"quality":{"id":21,"name":"Bluray-576p"},"items":[],"allowed":true},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":false},{"id":1001,"name":"WEB 720p","allowed":false,"items":[{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":false},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":false}]},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":false},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":false},{"id":1002,"name":"WEB 1080p","allowed":false,"items":[{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":false},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":false}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":false},{"quality":{"id":30,"name":"Remux-1080p"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false},{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":31,"name":"Remux-2160p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"BR-DISK"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false}]},
{"name":"HD-720p","upgradeAllowed":false,"cutoff":6,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"language":{"id":-2,"name":"Original"},"formatScores":{"x265 / HEVC":25},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":24,"name":"WORKPRINT"},"items":[],"allowed":false},{"quality":{"id":25,"name":"CAM"},"items":[],"allowed":false},{"quality":{"id":26,"name":"TELESYNC"},"items":[],"allowed":false},{"quality":{"id":27,"name":"TELECINE"},"items":[],"allowed":false},{"quality":{"id":29,"name":"REGIONAL"},"items":[],"allowed":false},{"quality":{"id":28,"name":"DVDSCR"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":23,"name":"DVD-R"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false}]},{"quality":{"id":20,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-576p"},"items":[],"allowed":false},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"id":1001,"name":"WEB 720p","allowed":true,"items":[{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true}]},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":false},{"id":1002,"name":"WEB 1080p","allowed":false,"items":[{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":false},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":false}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":false},{"quality":{"id":30,"name":"Remux-1080p"},"items":[],"allowed":false},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false},{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":31,"name":"Remux-2160p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"BR-DISK"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false}]},
{"name":"HD-1080p","upgradeAllowed":false,"cutoff":7,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"language":{"id":-2,"name":"Original"},"formatScores":{"x265 / HEVC":25},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":24,"name":"WORKPRINT"},"items":[],"allowed":false},{"quality":{"id":25,"name":"CAM"},"items":[],"allowed":false},{"quality":{"id":26,"name":"TELESYNC"},"items":[],"allowed":false},{"quality":{"id":27,"name":"TELECINE"},"items":[],"allowed":false},{"quality":{"id":29,"name":"REGIONAL"},"items":[],"allowed":false},{"quality":{"id":28,"name":"DVDSCR"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":23,"name":"DVD-R"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false}]},{"quality":{"id":20,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-576p"},"items":[],"allowed":false},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":false},{"id":1001,"name":"WEB 720p","allowed":false,"items":[{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":false},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":false}]},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":false},{"quality":{"id":30,"name":"Remux-1080p"},"items":[],"allowed":true},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"id":1002,"name":"WEB 1080p","allowed":true,"items":[{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true}]},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false},{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":31,"name":"Remux-2160p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"BR-DISK"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false}]},
{"name":"HD - 720p/1080p","upgradeAllowed":false,"cutoff":6,"minFormatScore":0,"cutoffFormatScore":0,"minUpgradeFormatScore":1,"language":{"id":-2,"name":"Original"},"formatScores":{"x265 / HEVC":25},"items":[{"quality":{"id":0,"name":"Unknown"},"items":[],"allowed":false},{"quality":{"id":24,"name":"WORKPRINT"},"items":[],"allowed":false},{"quality":{"id":25,"name":"CAM"},"items":[],"allowed":false},{"quality":{"id":26,"name":"TELESYNC"},"items":[],"allowed":false},{"quality":{"id":27,"name":"TELECINE"},"items":[],"allowed":false},{"quality":{"id":29,"name":"REGIONAL"},"items":[],"allowed":false},{"quality":{"id":28,"name":"DVDSCR"},"items":[],"allowed":false},{"quality":{"id":1,"name":"SDTV"},"items":[],"allowed":false},{"quality":{"id":2,"name":"DVD"},"items":[],"allowed":false},{"quality":{"id":23,"name":"DVD-R"},"items":[],"allowed":false},{"id":1000,"name":"WEB 480p","allowed":false,"items":[{"quality":{"id":8,"name":"WEBDL-480p"},"items":[],"allowed":false},{"quality":{"id":12,"name":"WEBRip-480p"},"items":[],"allowed":false}]},{"quality":{"id":20,"name":"Bluray-480p"},"items":[],"allowed":false},{"quality":{"id":21,"name":"Bluray-576p"},"items":[],"allowed":false},{"id":1002,"name":"WEB 1080p","allowed":true,"items":[{"quality":{"id":3,"name":"WEBDL-1080p"},"items":[],"allowed":true},{"quality":{"id":15,"name":"WEBRip-1080p"},"items":[],"allowed":true}]},{"quality":{"id":9,"name":"HDTV-1080p"},"items":[],"allowed":true},{"quality":{"id":7,"name":"Bluray-1080p"},"items":[],"allowed":true},{"quality":{"id":30,"name":"Remux-1080p"},"items":[],"allowed":true},{"id":1001,"name":"WEB 720p","allowed":true,"items":[{"quality":{"id":5,"name":"WEBDL-720p"},"items":[],"allowed":true},{"quality":{"id":14,"name":"WEBRip-720p"},"items":[],"allowed":true}]},{"quality":{"id":4,"name":"HDTV-720p"},"items":[],"allowed":true},{"quality":{"id":6,"name":"Bluray-720p"},"items":[],"allowed":true},{"quality":{"id":16,"name":"HDTV-2160p"},"items":[],"allowed":false},{"id":1003,"name":"WEB 2160p","allowed":false,"items":[{"quality":{"id":18,"name":"WEBDL-2160p"},"items":[],"allowed":false},{"quality":{"id":17,"name":"WEBRip-2160p"},"items":[],"allowed":false}]},{"quality":{"id":19,"name":"Bluray-2160p"},"items":[],"allowed":false},{"quality":{"id":31,"name":"Remux-2160p"},"items":[],"allowed":false},{"quality":{"id":22,"name":"BR-DISK"},"items":[],"allowed":false},{"quality":{"id":10,"name":"Raw-HD"},"items":[],"allowed":false}]}
],"removeProfiles":["Ultra-HD"],"qualityDefinitions":[
{"quality":"Unknown","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"WORKPRINT","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"CAM","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"TELESYNC","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"TELECINE","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"REGIONAL","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"DVDSCR","minSize":0,"maxSize":100,"preferredSize":95},
{"quality":"SDTV","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"DVD","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"DVD-R","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"WEBDL-480p","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"WEBRip-480p","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"Bluray-480p","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"Bluray-576p","minSize":2,"maxSize":20,"preferredSize":8},
{"quality":"HDTV-720p","minSize":5,"maxSize":35,"preferredSize":15},
{"quality":"WEBDL-720p","minSize":5,"maxSize":35,"preferredSize":15},
{"quality":"WEBRip-720p","minSize":5,"maxSize":35,"preferredSize":15},
{"quality":"Bluray-720p","minSize":5,"maxSize":35,"preferredSize":15},
{"quality":"HDTV-1080p","minSize":10,"maxSize":58,"preferredSize":28},
{"quality":"WEBDL-1080p","minSize":10,"maxSize":58,"preferredSize":28},
{"quality":"WEBRip-1080p","minSize":10,"maxSize":58,"preferredSize":28},
{"quality":"Bluray-1080p","minSize":10,"maxSize":58,"preferredSize":28},
{"quality":"Remux-1080p","minSize":60,"maxSize":200,"preferredSize":120},
{"quality":"HDTV-2160p","minSize":25,"maxSize":120,"preferredSize":60},
{"quality":"WEBDL-2160p","minSize":25,"maxSize":120,"preferredSize":60},
{"quality":"WEBRip-2160p","minSize":25,"maxSize":120,"preferredSize":60},
{"quality":"Bluray-2160p","minSize":25,"maxSize":120,"preferredSize":60},
{"quality":"Remux-2160p","minSize":150,"maxSize":400,"preferredSize":250},
{"quality":"BR-DISK","minSize":0,"maxSize":null,"preferredSize":null},
{"quality":"Raw-HD","minSize":0,"maxSize":null,"preferredSize":null}
],"releaseProfiles":[

]}
JSON
            ;;
        *) return 1 ;;
    esac
}

arrq_name() { case "$1" in sonarr) printf Sonarr ;; radarr) printf Radarr ;; *) printf '%s' "$1" ;; esac; }

ARRQ_IN=''          # the app's current settings and the defaults, as one JSON file for arrq_changes
ARRQ_ERR=''         # why arrq_fetch failed
ARRQ_SEP=$(printf '\037')

# Read the app's current settings: custom formats, quality profiles and the profile template
# (every quality the app knows), quality sizes and Sonarr's release profiles.
arrq_fetch() {      # app url key -> 0 when every read worked
    local app=$1 url=$2 key=$3 cf qp schema qd rp='[]'
    ARRQ_ERR=''
    api_call GET "$url/api/v3/customformat" "$key" || { ARRQ_ERR="custom formats: $(arrq_status)"; return 1; }
    cf=$API_BODY
    api_call GET "$url/api/v3/qualityprofile" "$key" || { ARRQ_ERR="quality profiles: $(arrq_status)"; return 1; }
    qp=$API_BODY
    api_call GET "$url/api/v3/qualityprofile/schema" "$key" || { ARRQ_ERR="the profile template: $(arrq_status)"; return 1; }
    schema=$API_BODY
    api_call GET "$url/api/v3/qualitydefinition" "$key" || { ARRQ_ERR="quality sizes: $(arrq_status)"; return 1; }
    qd=$API_BODY
    if [ "$app" = sonarr ]; then
        api_call GET "$url/api/v3/releaseprofile" "$key" || { ARRQ_ERR="release profiles: $(arrq_status)"; return 1; }
        rp=$API_BODY
    fi
    [ -n "$ARRQ_IN" ] || ARRQ_IN=$(mktemp "${TMPDIR:-/tmp}/kit-arrq.XXXXXX") || { ARRQ_ERR="no temp file"; return 1; }
    { printf '{"data":'; arrq_data "$app"
      printf ',"cf":%s,"qp":%s,"schema":%s,"qd":%s,"rp":%s}' "$cf" "$qp" "$schema" "$qd" "$rp"; } >"$ARRQ_IN"
}
arrq_status() { case "$API_STATUS" in 000) printf 'no answer' ;; *) printf 'HTTP %s' "$API_STATUS" ;; esac; }
arrq_done() { [ -z "$ARRQ_IN" ] || rm -f "$ARRQ_IN"; ARRQ_IN=''; }

# What to change, from the file arrq_fetch wrote: one line per change,
#   METHOD<US>api-path<US>what<US>json   (US: ARRQ_SEP, the unit separator, so empty fields stay)
# Phase formats is the custom formats; phase rest is everything else, which needs the formats' ids
# (so fetch again between the two). Only for an app with its stock settings (arrq_stock): it has
# no custom formats or release profiles, and its profiles are the stock ones, changed in place
# when they differ, with the stock profiles the defaults drop removed.
arrq_changes() {    # formats|rest
    [ -n "$ARRQ_IN" ] || return 1
    osascript -l JavaScript -e 'ObjC.import("Foundation");
function run(argv) {
    var S = JSON.parse($.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null).js);
    var phase = argv[1], D = S.data, out = [];
    function line(m, p, what, body) { out.push([m, p, what, body === undefined ? "" : JSON.stringify(body)].join("\u001f")); }
    // want is in have: every key of want has the same value in have (have may hold more)
    function sub(want, have) {
        if (want === null || typeof want !== "object") return want === have;
        if (have === null || typeof have !== "object") return false;
        if (Array.isArray(want)) {
            if (!Array.isArray(have) || want.length !== have.length) return false;
            for (var i = 0; i < want.length; i++) if (!sub(want[i], have[i])) return false;
            return true;
        }
        for (var k in want) if (!sub(want[k], have[k])) return false;
        return true;
    }
    function byName(list, n) { for (var i = 0; i < list.length; i++) if (list[i].name === n) return list[i]; return null; }
    if (phase === "formats") {
        D.customFormats.forEach(function (f) {
            if (!byName(S.cf, f.name)) line("POST", "customformat", "custom format " + f.name, f);
        });
        return out.join("\n");
    }
    // Every quality the app knows, from its profile template
    var known = {}, all = [];
    (function walk(items) { items.forEach(function (i) {
        if (i.items && i.items.length) walk(i.items); else if (i.quality) { known[i.quality.id] = true; all.push(i.quality); }
    }); })(S.schema.items || []);
    function items(list) {
        var seen = {}, res = [];
        list.forEach(function (i) {
            if (i.items && i.items.length) {
                var inner = i.items.filter(function (x) { return known[x.quality.id]; });
                inner.forEach(function (x) { seen[x.quality.id] = true; });
                if (inner.length) res.push({ id: i.id, name: i.name, allowed: i.allowed, items: inner });
            } else if (known[i.quality.id]) { seen[i.quality.id] = true; res.push(i); }
        });
        all.filter(function (q) { return !seen[q.id]; }).reverse().forEach(function (q) {
            res.unshift({ quality: { id: q.id, name: q.name }, items: [], allowed: false });
        });
        return res;
    }
    function scores(p) {            // name -> score, for every custom format the app has
        var s = {};
        S.cf.forEach(function (f) { s[f.name] = p.formatScores.hasOwnProperty(f.name) ? p.formatScores[f.name] : 0; });
        return s;
    }
    D.qualityProfiles.forEach(function (p) {
        var have = byName(S.qp, p.name), b = have ? { id: have.id } : {}, sc, same, hs = {};
        ["name", "upgradeAllowed", "cutoff", "minFormatScore", "cutoffFormatScore", "minUpgradeFormatScore", "language"]
            .forEach(function (k) { if (p.hasOwnProperty(k)) b[k] = p[k]; });
        b.items = items(p.items);
        sc = scores(p);
        b.formatItems = S.cf.map(function (f) { return { format: f.id, name: f.name, score: sc[f.name] }; });
        if (!have) return line("POST", "qualityprofile", "quality profile " + p.name, b);
        (have.formatItems || []).forEach(function (x) { hs[x.name] = x.score; });
        same = Object.keys(sc).every(function (n) { return (hs[n] || 0) === sc[n]; });
        var cmp = JSON.parse(JSON.stringify(b)); delete cmp.formatItems;
        if (same && sub(cmp, have)) return;
        line("PUT", "qualityprofile/" + have.id, "quality profile " + p.name + " (updated)", b);
    });
    S.qp.forEach(function (h) {
        if (!byName(D.qualityProfiles, h.name) && D.removeProfiles.indexOf(h.name) >= 0)
            line("DELETE", "qualityprofile/" + h.id, "quality profile " + h.name + " removed (not one of the defaults)");
    });
    var defs = [], n = 0;
    S.qd.forEach(function (h) {
        var w = null;
        D.qualityDefinitions.forEach(function (d) { if (d.quality === h.quality.name) w = d; });
        if (!w) return;
        if (w.minSize === h.minSize && (w.maxSize === null ? h.maxSize == null : w.maxSize === h.maxSize)
            && (w.preferredSize === null ? h.preferredSize == null : w.preferredSize === h.preferredSize)) return;
        var b = JSON.parse(JSON.stringify(h));
        b.minSize = w.minSize; b.maxSize = w.maxSize; b.preferredSize = w.preferredSize;
        defs.push(b); n++;
    });
    if (n) line("PUT", "qualitydefinition/update", "quality sizes (" + n + " " + (n === 1 ? "quality" : "qualities") + ")", defs);
    (D.releaseProfiles || []).forEach(function (r) {
        if (!byName(S.rp, r.name)) line("POST", "releaseprofile", "release profile " + r.name, Object.assign({}, r, { indexerId: 0, tags: [] }));
    });
    return out.join("\n");
}' "$ARRQ_IN" "$1" 2>/dev/null
}

# Whether the app still has its stock settings, so the defaults can go in without replacing
# anyone's: no custom formats, no release profiles, only the stock profiles (by name) and nothing
# in its library yet. 0 yes, 1 no (ARRQ_ERR says why), 2 couldn't tell (ARRQ_ERR says why), as
# with no profiles at all: an app makes its stock ones as it starts, after which seeding is safe.
ARRQ_STOCK_PROFILES='Any|SD|HD-720p|HD-1080p|Ultra-HD|HD - 720p/1080p'
arrq_stock() {      # app url key
    local app=$1 url=$2 key=$3 n
    api_call GET "$url/api/v3/customformat" "$key" || { ARRQ_ERR="custom formats: $(arrq_status)"; return 2; }
    arrq_empty || { ARRQ_ERR="it has custom formats"; return 1; }
    if [ "$app" = sonarr ]; then
        api_call GET "$url/api/v3/releaseprofile" "$key" || { ARRQ_ERR="release profiles: $(arrq_status)"; return 2; }
        arrq_empty || { ARRQ_ERR="it has release profiles"; return 1; }
    fi
    api_call GET "$url/api/v3/qualityprofile" "$key" || { ARRQ_ERR="quality profiles: $(arrq_status)"; return 2; }
    n=$(osascript -l JavaScript -e 'function run(argv) {
    var d = JSON.parse(argv[1]), stock = argv[0].split("|");
    if (!d.length) return "none";
    return d.filter(function (p) { return stock.indexOf(p.name) < 0; }).length; }' "$ARRQ_STOCK_PROFILES" "$API_BODY" 2>/dev/null)
    case "$n" in
        0) ;;
        [0-9]*) ARRQ_ERR="it has quality profiles of its own"; return 1 ;;
        none) ARRQ_ERR="no profiles yet: it's still starting"; return 2 ;;    # it makes its stock ones at its first start
        *) ARRQ_ERR="couldn't read its quality profiles"; return 2 ;;
    esac
    case "$app" in sonarr) n=series ;; *) n=movie ;; esac
    api_call GET "$url/api/v3/$n" "$key" || { ARRQ_ERR="its library: $(arrq_status)"; return 2; }
    arrq_empty || { ARRQ_ERR="its library isn't empty"; return 1; }
    return 0
}
arrq_empty() { [ "$(printf '%s' "$API_BODY" | tr -d ' \n\t\r')" = '[]' ]; }

# Put the defaults in: the custom formats first, then (with their ids) the rest. Says what it did
# with ok, what failed with warn; returns 1 when something failed.
arrq_seed() {       # app url key
    local app=$1 url=$2 key=$3 phase name m p what body bad=0
    name=$(arrq_name "$app")
    for phase in formats rest; do
        if ! arrq_fetch "$app" "$url" "$key"; then
            warn "$name: couldn't read its quality settings ($ARRQ_ERR)"
            arrq_done
            return 1
        fi
        while IFS="$ARRQ_SEP" read -r m p what body; do
            [ -n "$m" ] || continue
            if api_call "$m" "$url/api/v3/$p" "$key" ${body:+"$body"}; then
                ok "$name: $what"
            else
                warn "$name: $what: $(arrq_status)$(arrq_message)"
                bad=1
            fi
        done <<EOF
$(arrq_changes "$phase")
EOF
    done
    arrq_done
    return "$bad"
}
arrq_message() {    # the app's first error message in the last answer, as ": message"
    local m
    m=$(printf '%s' "$API_BODY" | tr -d '\n' | sed -n 's/.*"errorMessage" *: *"\([^"]*\)".*/\1/p' | head -n 1)
    [ -z "$m" ] || printf ': %s' "$m"
}
