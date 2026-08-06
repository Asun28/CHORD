import Foundation

/// What Ask needs from an inference client: the four model contracts, plus honest
/// answers to two questions the board has to display —
/// *is an endpoint configured?* and *did a model actually write that text?*
///
/// The second one matters because `CompositeInferenceClient` falls back to the
/// deterministic offline client when the endpoint is cold. That fallback is the
/// right behaviour — the board must never break because a model is unavailable —
/// but presenting its output as a model summary would be a lie on a projector
/// (architecture.md §7, ADR-007).
///
/// Ask depends on this protocol rather than on a concrete client so the endpoint
/// stays configuration and the degraded tier stays testable. No provider named.
public protocol AskInferenceClient: InferenceClient {
    var isRemoteConfigured: Bool { get }
    var lastAnswerCameFromModel: Bool { get }
}

extension CompositeInferenceClient: AskInferenceClient {}
