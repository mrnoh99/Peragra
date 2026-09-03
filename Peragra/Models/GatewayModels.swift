import Foundation

/// Model IDs available on the factchat-cloud.mindlogic.ai gateway, as
/// listed on its own "API Gateway" docs page. Not necessarily exhaustive —
/// the Settings model picker also accepts a custom ID for anything not
/// listed here (the gateway may add models this list doesn't know about).
/// Mirrors web/src/lib/gatewayModels.ts.
enum GatewayModels {
    struct Model: Identifiable {
        let id: String
        let label: String
    }

    static let all: [Model] = [
        Model(id: "claude-sonnet-5", label: "Claude Sonnet 5"),
        Model(id: "claude-opus-5", label: "Claude Opus 5"),
        Model(id: "claude-fable-5-1", label: "Claude Fable 5.1"),
        Model(id: "claude-fable-5", label: "Claude Fable 5"),
        Model(id: "gpt-5.6-luna", label: "GPT-5.6 Luna"),
        Model(id: "gpt-5.6-terra", label: "GPT-5.6 Terra"),
        Model(id: "gpt-5.6-sol", label: "GPT-5.6 Sol"),
        Model(id: "gpt-5.5", label: "GPT-5.5"),
    ]

    static let defaultModel = "claude-sonnet-5"
}
