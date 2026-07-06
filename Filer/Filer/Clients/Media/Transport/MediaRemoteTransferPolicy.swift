import Foundation

/// Tuning limits shared by the two media transfer engines: `MediaUploadClient`
/// (TUS resumable upload) and `MediaDownloadClient` (HTTP range download).
///
/// It captures two concerns:
/// - **Chunking** — how large each transferred slice is (`chunkSize`).
/// - **Resilience** — how an engine reacts to a failed request: how many times to
///   retry, resume, or recreate, and how long to wait between attempts.
///
/// Not every field applies to both engines; each property documents where it is
/// used. A single shared `default` keeps upload and download consistent; tests
/// build focused variants (e.g. `MediaDownloadClientTests.policy(chunkSize:)`).
///
/// Example:
/// ```swift
/// let uploader = MediaUploadClient(
///     transport: .live(session: .shared),
///     retryPolicy: .default,        // this type
///     connectivity: .live,
///     sleeper: .live
/// )
/// ```
struct MediaRemoteTransferPolicy: Equatable, Sendable {
    /// Bytes per transferred slice — one TUS PATCH body (upload) or one ranged
    /// GET window (download). Larger means fewer round trips but more to re-send
    /// on a failed slice. Used by **both** engines.
    let chunkSize: Int

    /// Max retries for a single failed ranged GET before the download fails.
    /// Used by **download** only (`MediaDownloadClient`).
    let maxRetries: Int

    /// Max reconnect attempts per stall when an upload chunk hits a retryable
    /// (connectivity) error. Each attempt waits for connectivity, then re-reads
    /// the server offset via a TUS HEAD. The budget is *per stall* — forward
    /// progress effectively refills it — so a long upload survives repeated brief
    /// drops. Used by **upload** only (`MediaUploadClient`).
    let maxResumes: Int

    /// Max times an upload may recreate its TUS session (a fresh POST) after a
    /// conflict/gone response (409/410/404) before failing. Unlike a connectivity
    /// resume, recreating restarts the upload from offset 0. Used by **upload**
    /// only (`MediaUploadClient`).
    let maxRecreates: Int

    /// Base delay (seconds) before the first HEAD retry within a reconnect
    /// attempt. Used by **upload** only. See `resumeBackoff(_:)`.
    let resumeBackoffBase: TimeInterval

    /// Growth factor applied to the backoff on each subsequent HEAD retry.
    /// Used by **upload** only. See `resumeBackoff(_:)`.
    let resumeBackoffMultiplier: Double

    /// Ceiling (seconds) on any single backoff delay, keeping the wait bounded.
    /// Used by **upload** only. See `resumeBackoff(_:)`.
    let resumeBackoffCap: TimeInterval

    /// Max time (seconds) to wait for connectivity to return before attempting a
    /// HEAD anyway. Bounds each reconnect attempt so it never blocks forever when
    /// no connectivity event arrives. Used by **upload** only.
    let connectivityWaitTimeout: TimeInterval

    /// Per-request timeout (seconds) applied to every TUS request, so a mid-flight
    /// drop surfaces as an error within seconds instead of waiting out URLSession's
    /// 60s default. Used by **upload** only.
    let requestTimeout: TimeInterval

    /// The five reconnection fields carry defaults so existing call sites — and the
    /// download engine, which ignores them — need not specify them.
    init(
        chunkSize: Int,
        maxRetries: Int,
        maxResumes: Int,
        maxRecreates: Int,
        resumeBackoffBase: TimeInterval = 1,
        resumeBackoffMultiplier: Double = 2,
        resumeBackoffCap: TimeInterval = 8,
        connectivityWaitTimeout: TimeInterval = 20,
        requestTimeout: TimeInterval = 15
    ) {
        self.chunkSize = chunkSize
        self.maxRetries = maxRetries
        self.maxResumes = maxResumes
        self.maxRecreates = maxRecreates
        self.resumeBackoffBase = resumeBackoffBase
        self.resumeBackoffMultiplier = resumeBackoffMultiplier
        self.resumeBackoffCap = resumeBackoffCap
        self.connectivityWaitTimeout = connectivityWaitTimeout
        self.requestTimeout = requestTimeout
    }

    /// Shared default used by both live engines.
    static let `default` = MediaRemoteTransferPolicy(
        chunkSize: 6 * 1024 * 1024,
        maxRetries: 2,
        maxResumes: 3,
        maxRecreates: 1
    )

    /// Whether `error` warrants a retry/resume: a transport-level `URLError` that
    /// is not an explicit cancellation. Protocol-level failures (bad status or
    /// malformed response) are excluded — callers handle those separately.
    /// Used by **both** engines.
    func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code != .cancelled
    }

    /// Exponential backoff for reconnect attempt `1, 2, 3, …`:
    /// `min(resumeBackoffBase × resumeBackoffMultiplier^(attempt - 1), resumeBackoffCap)`.
    /// With the defaults: 1s, 2s, 4s, 8s, 8s… Used by **upload** only.
    func resumeBackoff(_ attempt: Int) -> TimeInterval {
        let exponent = Double(max(attempt - 1, 0))
        let raw = resumeBackoffBase * pow(resumeBackoffMultiplier, exponent)
        return min(raw, resumeBackoffCap)
    }
}
