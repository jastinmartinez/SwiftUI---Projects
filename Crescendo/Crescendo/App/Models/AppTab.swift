/// Identifies Crescendo's peer application-level destinations.
///
/// This value owns stable tab identity only. It does not own feature state,
/// selection effects, navigation, tab rendering, or playback presentation.
enum AppTab: Hashable, Sendable {
    case search
    case library
}
