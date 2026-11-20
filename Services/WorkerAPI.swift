import Foundation

// Every call to the job worker goes through these sessions so it carries the app key; the
// worker answers 401 without it. Calls to other sites keep using URLSession.shared.
enum WorkerAPI {
    static let session = URLSession(configuration: configuration())

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["X-App-Key": Secrets.appKey]
        return config
    }
}
