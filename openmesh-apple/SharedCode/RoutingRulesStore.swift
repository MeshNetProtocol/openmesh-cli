import Foundation

/// Deprecated: RoutingRulesStore is no longer used as the system now relies on
/// provider-specific routing_rules.json files instead of a bundled global one.
enum RoutingRulesStore {
    // This enum is kept empty to avoid breaking potential lingering references
    // during the transition, but all syncing logic has been removed.
}
