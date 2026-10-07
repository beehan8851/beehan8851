import Foundation

/// Explicit loading state for feature view models.
/// `.empty` indicates a successful load with zero items (distinct from loading/failure).
enum FeatureLoadState<T> {
    case idle
    case loading
    case loaded(T)   // T is guaranteed non-empty by convention
    case empty
    case failure(Error)
}
