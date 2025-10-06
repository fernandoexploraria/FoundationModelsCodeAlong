import Foundation

public enum Continent: String {
    case africa = "Africa"
    case antarctica = "Antarctica"
    case asia = "Asia"
    case europe = "Europe"
    case america = "America"      // Single bucket for North/Central/South/Caribbean
    case oceania = "Oceania"
}

public enum ContinentLookup {
    /// Returns the Continent for a given Locale.Region using ISO 3166-1 alpha-2 codes.
    public static func continent(for region: Locale.Region?) -> Continent? {
        guard let code = region?.identifier.uppercased() else { return nil }
        return map[code]
    }

    /// Convenience to return the continent name string (e.g., "America", "Europe").
    public static func continentName(for region: Locale.Region?) -> String? {
        continent(for: region)?.rawValue
    }

    // MARK: - Mapping
    // Note: This is a pragmatic mapping focused on broad coverage. Unknown codes return nil.
    private static let map: [String: Continent] = {
        var m: [String: Continent] = [:]

        // America (North, Central, Caribbean, South, and nearby territories)
        let americaCodes = [
            // North America core
            "US", "CA", "MX",
            // Central America
            "BZ", "GT", "SV", "HN", "NI", "CR", "PA",
            // Caribbean (including territories)
            "AG", "AI", "AW", "BB", "BL", "BQ", "BS", "CU", "CW", "DM", "DO", "GD", "GP", "HT", "JM", "KN", "KY", "LC", "MF", "MQ", "MS", "SX", "TC", "TT", "VC", "VG", "VI", "PR", "BM",
            // North Atlantic territories associated with America
            "GL", "PM",
            // South America
            "AR", "BO", "BR", "CL", "CO", "EC", "FK", "GF", "GY", "PE", "PY", "SR", "UY", "VE"
        ]
        for code in americaCodes { m[code] = .america }

        // Antarctica and subantarctic territories
        let antarcticaCodes = ["AQ", "BV", "GS", "HM", "TF"]
        for code in antarcticaCodes { m[code] = .antarctica }

        // Europe (representative, broad coverage)
        let europeCodes = [
            "AD", "AL", "AT", "AX", "BA", "BE", "BG", "BY", "CH", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "FO", "FR", "GB", "GG", "GI", "GR", "HR", "HU", "IE", "IM", "IS", "IT", "JE", "LI", "LT", "LU", "LV", "MC", "MD", "ME", "MK", "MT", "NL", "NO", "PL", "PT", "RO", "RS", "RU", "SE", "SI", "SJ", "SK", "SM", "UA", "VA"
        ]
        for code in europeCodes { m[code] = .europe }

        // Asia (including Middle East and Central Asia)
        let asiaCodes = [
            "AE", "AF", "AM", "AZ", "BD", "BH", "BN", "BT", "CN", "GE", "HK", "ID", "IL", "IN", "IQ", "IR", "JO", "JP", "KG", "KH", "KP", "KR", "KW", "KZ", "LA", "LB", "LK", "MM", "MN", "MO", "MV", "MY", "NP", "OM", "PH", "PK", "PS", "QA", "SA", "SG", "SY", "TH", "TJ", "TL", "TM", "TR", "TW", "UZ", "VN", "YE"
        ]
        for code in asiaCodes { m[code] = .asia }

        // Africa
        let africaCodes = [
            "AO", "BF", "BI", "BJ", "BW", "CD", "CF", "CG", "CI", "CM", "CV", "DJ", "DZ", "EG", "EH", "ER", "ET", "GA", "GH", "GM", "GN", "GQ", "GW", "KE", "KM", "LR", "LS", "LY", "MA", "MG", "ML", "MR", "MU", "MW", "MZ", "NA", "NE", "NG", "RE", "RW", "SC", "SD", "SH", "SL", "SN", "SO", "SS", "ST", "SZ", "TD", "TG", "TN", "TZ", "UG", "YT", "ZA", "ZM", "ZW"
        ]
        for code in africaCodes { m[code] = .africa }

        // Oceania
        let oceaniaCodes = [
            "AS", "AU", "CK", "FJ", "FM", "GU", "KI", "MH", "MP", "NC", "NF", "NR", "NU", "NZ", "PF", "PG", "PN", "PW", "SB", "TK", "TO", "TV", "UM", "VU", "WF", "WS"
        ]
        for code in oceaniaCodes { m[code] = .oceania }

        return m
    }()
}
