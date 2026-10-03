import Foundation

// From Android's domain/ComingUp.kt: so far only the weekend days, which the "This week" outlook needs (see
// [weekOutlook]). The rest of Coming up (holidays, long weekends, countdowns) isn't ported yet.

private let satSun: Set<DayOfWeek> = [.saturday, .sunday]
private let friSat: Set<DayOfWeek> = [.friday, .saturday]

/// Countries whose weekend isn't Saturday and Sunday (ISO codes).
private let weekends: [String: Set<DayOfWeek>] =
    Dictionary(uniqueKeysWithValues: ["BH", "BD", "DZ", "EG", "IL", "IQ", "JO", "KW", "LY", "MV", "OM", "QA", "SA", "SD", "SY", "YE"]
        .map { ($0, friSat) })
        .merging([
            "AF": [.friday],
            "IR": [.friday],
            "SO": [.thursday, .friday],
            "BN": [.friday, .sunday],
            "NP": [.saturday],
        ]) { _, new in new }

/// The usual weekend days in a country; Saturday and Sunday when unknown.
func weekendDays(_ countryCode: String?) -> Set<DayOfWeek> { countryCode.flatMap { weekends[$0.uppercased()] } ?? satSun }
