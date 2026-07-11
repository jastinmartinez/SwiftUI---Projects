import Foundation

extension Sleeper {
    static let live = Sleeper { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }
}
