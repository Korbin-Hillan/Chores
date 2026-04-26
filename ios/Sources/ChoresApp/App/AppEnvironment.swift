import Foundation

enum AppEnvironment {
    static let apiBaseURL: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ApiBaseURL") as? String ?? ""
        if let url = URL(string: raw), !raw.isEmpty {
            return url
        }
        return URL(string: "https://choresapp-api.onrender.com")!
    }()
}
