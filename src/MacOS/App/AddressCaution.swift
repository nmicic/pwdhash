import Foundation

/// A notice about the part of an address the original algorithm reads as the site name.
///
/// The algorithm is kept exactly as published, so an address is never rejected, trimmed or
/// rewritten and the generated password never changes because of this check. The notice exists
/// because a pasted link can name one site to a browser and another to the algorithm, and because
/// a stray invisible character silently changes the result.
///
/// A plain name such as `example.com` or `name.SUFFIX`, in any letter case, never produces one.
enum AddressCaution {
    /// The text the algorithm splits into labels: the address without the first `http://` and the
    /// first `https://`, up to the next slash. These are the same Foundation calls as
    /// `LegacyPwdHash.domain(for:)`, so both read an address identically.
    static func sitePart(of address: String) -> String? {
        var host = address
        for prefix in ["http://", "https://"] {
            if let range = host.range(of: prefix, options: .literal) { host.removeSubrange(range) }
        }
        return host.components(separatedBy: "/").first(where: { !$0.isEmpty })
    }

    static func message(for address: String) -> String? {
        guard let site = sitePart(of: address) else { return nil }
        let scalars = Array(site.unicodeScalars)
        guard let index = scalars.firstIndex(where: isUnusual) else { return nil }
        let scalar = scalars[index]
        let lead = "Caution: the site part of the address contains \(name(of: scalar))."
        switch scalar {
        case ":" where index == scalars.count - 1:
            return "Caution: only lowercase “http://” and “https://” are removed from an address. Here the original algorithm reads “\(printable(site))” as the site name, so every address that starts this way gives the same result."
        case ":":
            return "\(lead) The original algorithm does not separate a port or user name from the site name, so the result can differ from the same site without it."
        case "#", "?", "\\":
            return "\(lead) A browser ends the site name there, but the original algorithm reads on, so the hashing domain may not be the site a link opens."
        case "@":
            return "\(lead) A browser treats the text before it as a user name, so the hashing domain may not be the site a link opens."
        case "%":
            return "\(lead) A browser decodes percent codes in a site name, but the original algorithm hashes them as written."
        default:
            if scalar.value < 0x80 {
                return "\(lead) Nothing is trimmed, so the result can differ from the same address without it."
            }
            return "\(lead) The original algorithm keeps only part of each non-ASCII character, so different names can give the same password."
        }
    }

    private static func isUnusual(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x21 || scalar.value >= 0x7F { return true }
        return "#%:?@\\".unicodeScalars.contains(scalar)
    }

    private static func code(_ scalar: Unicode.Scalar) -> String {
        "U+" + String(scalar.value, radix: 16, uppercase: true).leftPadded(to: 4)
    }

    private static func name(of scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x20: return "a space"
        case 0x09: return "a tab"
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: return "a line break"
        case 0x21..<0x7F: return "“\(scalar)”"
        case ..<0x20, 0x7F..<0xA0: return "a control character (\(code(scalar)))"
        default: break
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber,
             .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return "“\(scalar)” (\(code(scalar)))"
        default:
            // Combining marks, format characters, unusual spaces and unassigned code points.
            return "a character that may be invisible (\(code(scalar)))"
        }
    }

    /// The site part with anything that is not visible ASCII shown as its code point.
    private static func printable(_ text: String) -> String {
        text.unicodeScalars.map { (0x21..<0x7F).contains($0.value) ? String($0) : "<\(code($0))>" }.joined()
    }
}

private extension String {
    func leftPadded(to length: Int) -> String { String(repeating: "0", count: max(0, length - count)) + self }
}
