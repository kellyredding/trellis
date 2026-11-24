import Foundation
import Security

enum CodeSigning {
    /// The leaf certificate's summary, or how the app is signed without one.
    static var signer: String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unknown" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "unknown" }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return "unsigned" }
        if let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certificates.first,
           let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            return summary
        }
        return "ad hoc"
    }
}
