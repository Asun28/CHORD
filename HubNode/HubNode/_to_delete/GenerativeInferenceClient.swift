import Foundation

/// A client that can actually be asked to write prose, plus a runtime answer to
/// "is a model reachable right now?".
///
/// It has to be a runtime question rather than a type question, because
/// `CompositeInferenceClient` silently falls back to `OfflineInferenceClient`
/// when no endpoint is configured. Ask uses this to decide whether an answer is
/// labelled *summarised* or *not summarised — passages shown verbatim*. Claiming
/// a model spoke when none did is the failure mode this exists to prevent
/// (architecture.md §2, ADR-007).
///
/// No provider is named here on purpose: the endpoint stays configuration.
public protocol GenerativeInferenceClient: InferenceClient {
    var isModelAvailable: Bool { get }
}

/// The composite client is generative only while a remote endpoint is configured.
extension CompositeInferenceClient: GenerativeInferenceClient {
    var isModelAvailable: Bool { isRemoteConfigured }
}
