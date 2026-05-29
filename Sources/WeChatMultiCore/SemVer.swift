import Foundation

/// A lenient dotted-numeric version (e.g. "2.0.0", "1.8", "1.10.2").
///
/// Replaces the ad-hoc `versionIsNewer` that lived inline in AppDelegate.
/// Each dot-separated component contributes its leading integer, so
/// "1.8.0-beta" parses as [1, 8, 0]. Components are zero-padded for
/// comparison, so 1.8 == 1.8.0 and 1.10 > 1.9.
public struct SemVer: Comparable, Equatable, CustomStringConvertible {
    public let components: [Int]

    public init(_ string: String) {
        components = string.split(separator: ".").map { part in
            let leadingDigits = part.prefix { $0.isNumber }
            return Int(leadingDigits) ?? 0
        }
    }

    private func component(_ index: Int) -> Int {
        index < components.count ? components[index] : 0
    }

    public static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = lhs.component(i), r = rhs.component(i)
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: SemVer, rhs: SemVer) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count where lhs.component(i) != rhs.component(i) {
            return false
        }
        return true
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// Convenience matching the old call site's intent.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        SemVer(a) > SemVer(b)
    }
}
