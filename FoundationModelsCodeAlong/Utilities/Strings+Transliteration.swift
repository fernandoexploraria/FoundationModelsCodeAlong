import Foundation

extension String {
    /// Returns a basic Latin/ASCII transliteration of the string by removing diacritics
    /// and dropping non-ASCII scalars. This is intentionally lossy and minimal.
    var transliteratedLatinSafe: String {
        // Decompose to separate base characters from diacritics
        let decomposed = self.decomposedStringWithCanonicalMapping
        // Remove combining diacritic marks
        let noDiacriticsScalars = decomposed.unicodeScalars.filter { !$0.properties.isDiacritic }
        // Keep only ASCII scalars to be extra safe for model consumption
        let asciiScalars = noDiacriticsScalars.filter { $0.isASCII }
        return String(String.UnicodeScalarView(asciiScalars))
    }
}
