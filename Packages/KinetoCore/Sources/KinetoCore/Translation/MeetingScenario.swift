import Foundation

/// User-selected meeting situation used to keep live translations on-register.
///
/// Apple Translation sees one finalized clause at a time. Without a scenario it
/// often renders English meeting speech as literal Vietnamese (or the reverse)
/// that would never be said in that room.
public enum MeetingScenario: String, Codable, CaseIterable, Sendable, Identifiable {
    case general = "general"
    case standup = "standup"
    case planning = "planning"
    case oneOnOne = "one-on-one"
    case clientCall = "client-call"
    case interview = "interview"
    case lecture = "lecture"
    case support = "support"
    case sales = "sales"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: "General conversation"
        case .standup: "Standup / sync"
        case .planning: "Planning / sprint"
        case .oneOnOne: "One-on-one"
        case .clientCall: "Client call"
        case .interview: "Interview"
        case .lecture: "Lecture / workshop"
        case .support: "Support / incident"
        case .sales: "Sales / demo"
        }
    }

    public var detail: String {
        switch self {
        case .general:
            "Natural bilingual speech. Keep product names and keep meeting English that Vietnamese speakers already use."
        case .standup:
            "Engineering standup. Keep sprint, blocker, PR, deploy, ticket in English; do not turn “ship” into logistics."
        case .planning:
            "Planning and roadmap talk. Preserve backlog, spike, estimate, and owner-as-person-in-charge."
        case .oneOnOne:
            "Private manager/report talk. Softer register, career language, no courtroom formality."
        case .clientCall:
            "External customer meeting. Polite Vietnamese (anh/chị), keep company and product names."
        case .interview:
            "Hiring conversation. Keep role titles and interview prompts; do not over-formalize answers."
        case .lecture:
            "Teaching or workshop. Clear spoken Vietnamese; keep technical terms the speaker left in English."
        case .support:
            "Incident or customer support. Keep severity, ticket, rollback, and mitigation wording."
        case .sales:
            "Demo or commercial call. Persuasive but not ad-copy; keep pricing units and product names."
        }
    }

    /// Short instruction block for an on-device rewrite model.
    public var rewriteGuidance: String {
        switch self {
        case .general:
            "Speak the way bilingual colleagues actually talk. Do not invent honorifics the source did not imply."
        case .standup:
            "This is a software standup. Prefer the terms Vietnamese engineers already say in English: standup, blocker, PR, review, merge, deploy, rollback, ticket, sprint, backlog, spike, owner. “Ship” means release software, never freight. “Circle back” and “take offline” mean discuss later, not go offline or drive in a circle."
        case .planning:
            "This is sprint or roadmap planning. “Owner” is người phụ trách, not chủ sở hữu. “Estimate” is ước lượng effort, not a price quote unless money is explicit. Keep backlog, spike, story, and epic in English."
        case .oneOnOne:
            "This is a private 1:1. Use softer spoken Vietnamese. Career “level”, “promo”, and “feedback” stay recognizable. Do not make the manager sound like a legal notice."
        case .clientCall:
            "This is an external client meeting. Use polite anh/chị. Keep company, product, and people names. Do not translate slogans or SKUs."
        case .interview:
            "This is a job interview. Keep role titles. Questions should sound spoken, not like a translated exam paper."
        case .lecture:
            "This is teaching. Prefer clear spoken Vietnamese and leave the speaker’s English technical terms in English."
        case .support:
            "This is an incident or support call. Keep severity, ticket, rollback, mitigate, and outage in the form on-call engineers use. Do not soften a Sev-1 into casual chat."
        case .sales:
            "This is a product demo or commercial call. Sound like a real salesperson, not a brochure. Keep product names, plan names, and currency amounts."
        }
    }

    public var vietnameseRegisterNote: String {
        switch self {
        case .general, .standup, .planning, .support:
            "Peer software register: mình/bạn or no pronoun; keep English engineering nouns."
        case .oneOnOne:
            "Soft spoken register; avoid courtroom anh/chị stacking unless the source is already formal."
        case .clientCall, .sales:
            "Polite anh/chị toward the other party; do not use em unless the source is clearly junior."
        case .interview:
            "Candidate answers stay natural; interviewer prompts stay concise."
        case .lecture:
            "Teacher-to-room register; second person is các bạn unless a single person is addressed."
        }
    }
}
