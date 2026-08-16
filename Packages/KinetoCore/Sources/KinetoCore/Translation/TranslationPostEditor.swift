import Foundation

/// Deterministic rewrite of an Apple Translation draft so it matches the meeting.
///
/// Apple Translation is still the source of the first draft. This editor only
/// repairs known meeting-register failures, glossary collisions, and protected
/// tokens (names, tickets, identifiers). It never invents facts.
public struct TranslationPostEditor: Sendable {
    public init() {}

    public func edit(
        source: String,
        draft: String,
        sourceLanguage: SpokenLanguage,
        targetLanguage: SpokenLanguage,
        context: TranslationContext
    ) -> String {
        let sourceText = source.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty, !text.isEmpty else { return draft }

        let protected = ProtectedToken.extract(from: sourceText)
        if targetLanguage.isVietnamese {
            text = applyEnglishToVietnamesePhrases(source: sourceText, draft: text)
            text = applyEnglishToVietnameseGlossary(
                source: sourceText,
                draft: text,
                scenario: context.scenario
            )
        } else if targetLanguage.isEnglish {
            text = applyVietnameseToEnglishPhrases(source: sourceText, draft: text)
            text = applyVietnameseToEnglishGlossary(source: sourceText, draft: text)
        }
        text = ProtectedToken.restore(text, tokens: protected)
        return text
    }
}

private struct ProtectedToken {
    let placeholder: String
    let original: String

    static func extract(from source: String) -> [ProtectedToken] {
        let pattern = #"https?://\S+|[\w.+-]+@[\w.-]+\.\w+|`[^`]+`|\b[A-Z]{2,}[0-9]{1,6}\b|\b[A-Z][a-z]+[A-Z][A-Za-z0-9]+\b|\b[A-Z]{3,}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var tokens: [ProtectedToken] = []
        var seen = Set<String>()
        for match in regex.matches(in: source, range: range) {
            guard let swiftRange = Range(match.range, in: source) else { continue }
            let original = String(source[swiftRange])
            guard seen.insert(original).inserted else { continue }
            if Self.translatableAcronyms.contains(original.lowercased()) { continue }
            tokens.append(
                ProtectedToken(
                    placeholder: "⟦K\(tokens.count)⟧",
                    original: original
                )
            )
        }
        return tokens
    }

    static func restore(_ draft: String, tokens: [ProtectedToken]) -> String {
        var text = draft
        for token in tokens {
            if let range = text.range(
                of: token.original,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) {
                text.replaceSubrange(range, with: token.original)
                continue
            }
            if !text.isEmpty {
                text.append(" ")
            }
            text.append(token.original)
        }
        return text
    }

    private static let translatableAcronyms: Set<String> = [
        "ok", "fyi", "asap", "eta", "id",
    ]
}

private func applyEnglishToVietnamesePhrases(source: String, draft: String) -> String {
    var text = draft
    let folded = fold(source)
    for rule in englishToVietnamesePhrases where mentions(rule.trigger, in: folded) {
        for bad in rule.badDrafts {
            text = replaceCaseInsensitive(bad, with: rule.preferred, in: text)
        }
    }
    return text
}

private func applyEnglishToVietnameseGlossary(
    source: String,
    draft: String,
    scenario: MeetingScenario
) -> String {
    var text = draft
    let folded = fold(source)
    for entry in englishToVietnameseGlossary {
        guard mentions(entry.trigger, in: folded) else { continue }
        if let scenarios = entry.scenarios, !scenarios.contains(scenario) { continue }
        if scenario == .general, entry.needsSoftwareCue, !hasSoftwareReleaseCue(folded) {
            continue
        }
        for bad in entry.badDrafts {
            text = replaceCaseInsensitive(bad, with: entry.preferred, in: text)
        }
    }
    return text
}

private func applyVietnameseToEnglishPhrases(source: String, draft: String) -> String {
    var text = draft
    let folded = fold(source)
    for rule in vietnameseToEnglishPhrases where mentions(rule.trigger, in: folded) {
        for bad in rule.badDrafts {
            text = replaceCaseInsensitive(bad, with: rule.preferred, in: text)
        }
    }
    return text
}

private func applyVietnameseToEnglishGlossary(source: String, draft: String) -> String {
    var text = draft
    let folded = fold(source)
    for entry in vietnameseToEnglishGlossary {
        guard mentions(entry.trigger, in: folded) else { continue }
        for bad in entry.badDrafts {
            text = replaceCaseInsensitive(bad, with: entry.preferred, in: text)
        }
    }
    return text
}

private struct PhraseRule {
    let trigger: String
    let badDrafts: [String]
    let preferred: String
}

private struct GlossaryEntry {
    let trigger: String
    let badDrafts: [String]
    let preferred: String
    let scenarios: Set<MeetingScenario>?
    let needsSoftwareCue: Bool

    init(
        trigger: String,
        badDrafts: [String],
        preferred: String,
        scenarios: Set<MeetingScenario>? = nil,
        needsSoftwareCue: Bool = false
    ) {
        self.trigger = trigger
        self.badDrafts = badDrafts
        self.preferred = preferred
        self.scenarios = scenarios
        self.needsSoftwareCue = needsSoftwareCue
    }
}

private let englishToVietnamesePhrases: [PhraseRule] = [
    PhraseRule(
        trigger: "circle back",
        badDrafts: [
            "quay lại vòng tròn",
            "đi vòng tròn trở lại",
            "vòng lại",
            "circle back",
        ],
        preferred: "bàn lại sau"
    ),
    PhraseRule(
        trigger: "take this offline",
        badDrafts: ["đưa cái này ngoại tuyến", "mang cái này ra ngoại tuyến", "take this offline"],
        preferred: "bàn riêng sau"
    ),
    PhraseRule(
        trigger: "take it offline",
        badDrafts: ["đưa nó ra ngoại tuyến", "mang nó ra ngoại tuyến", "take it offline"],
        preferred: "bàn riêng sau"
    ),
    PhraseRule(
        trigger: "take offline",
        badDrafts: ["đưa ra ngoại tuyến", "mang ra ngoại tuyến"],
        preferred: "bàn riêng sau"
    ),
    PhraseRule(
        trigger: "sounds good",
        badDrafts: ["nghe có vẻ tốt", "nghe tốt", "sounds good"],
        preferred: "ok"
    ),
    PhraseRule(
        trigger: "looks good to me",
        badDrafts: ["trông tốt với tôi", "nhìn tốt với tôi", "looks good to me"],
        preferred: "ok, được"
    ),
    PhraseRule(
        trigger: "lgtm",
        badDrafts: ["lgtm"],
        preferred: "LGTM"
    ),
    PhraseRule(
        trigger: "hard stop",
        badDrafts: ["dừng cứng", "dừng cứng nhắc", "cứng dừng"],
        preferred: "phải dừng đúng giờ"
    ),
    PhraseRule(
        trigger: "park that",
        badDrafts: ["đỗ cái đó", "đậu cái đó", "park that"],
        preferred: "để lại sau"
    ),
    PhraseRule(
        trigger: "let's park",
        badDrafts: ["hãy đỗ", "hãy đậu"],
        preferred: "để lại"
    ),
    PhraseRule(
        trigger: "action item",
        badDrafts: ["mục hành động", "hạng mục hành động", "mục hành vi"],
        preferred: "việc cần làm"
    ),
    PhraseRule(
        trigger: "follow up",
        badDrafts: ["theo dõi", "đi theo"],
        preferred: "follow-up"
    ),
    PhraseRule(
        trigger: "follow-up",
        badDrafts: ["theo dõi", "đi theo"],
        preferred: "follow-up"
    ),
    PhraseRule(
        trigger: "ping me",
        badDrafts: ["ping tôi", "hãy ping tôi"],
        preferred: "nhắn mình"
    ),
    PhraseRule(
        trigger: "i hear you",
        badDrafts: ["tôi nghe bạn", "tôi nghe thấy bạn"],
        preferred: "mình hiểu"
    ),
    PhraseRule(
        trigger: "take a look",
        badDrafts: ["nhìn một cái", "lấy một cái nhìn", "đi nhìn"],
        preferred: "xem giúp"
    ),
    PhraseRule(
        trigger: "wrap up",
        badDrafts: ["bọc lại", "gói lại", "bọc gói"],
        preferred: "chốt lại"
    ),
    PhraseRule(
        trigger: "kick off",
        badDrafts: ["đá khởi đầu", "đá mở đầu"],
        preferred: "kickoff"
    ),
    PhraseRule(
        trigger: "kickoff",
        badDrafts: ["đá khởi đầu", "cú đá đầu"],
        preferred: "kickoff"
    ),
    PhraseRule(
        trigger: "deep dive",
        badDrafts: ["lặn sâu", "bơi sâu", "lặn sâu xuống"],
        preferred: "xem kỹ"
    ),
    PhraseRule(
        trigger: "bandwidth",
        badDrafts: ["băng thông"],
        preferred: "thời gian"
    ),
    PhraseRule(
        trigger: "loop in",
        badDrafts: ["vòng vào", "lặp vào"],
        preferred: "kéo vào"
    ),
    PhraseRule(
        trigger: "loop me in",
        badDrafts: ["vòng tôi vào", "lặp tôi vào"],
        preferred: "kéo mình vào"
    ),
    PhraseRule(
        trigger: "on the same page",
        badDrafts: ["trên cùng một trang", "cùng một trang"],
        preferred: "hiểu thống nhất"
    ),
    PhraseRule(
        trigger: "touch base",
        badDrafts: ["chạm đế", "chạm cơ sở", "chạm base"],
        preferred: "check-in nhanh"
    ),
    PhraseRule(
        trigger: "move the needle",
        badDrafts: ["di chuyển kim", "chuyển kim"],
        preferred: "tạo khác biệt thực sự"
    ),
    PhraseRule(
        trigger: "low hanging fruit",
        badDrafts: ["trái cây treo thấp", "quả treo thấp"],
        preferred: "việc dễ làm trước"
    ),
    PhraseRule(
        trigger: "no-brainer",
        badDrafts: ["không có não", "không bộ não"],
        preferred: "chuyện hiển nhiên"
    ),
    PhraseRule(
        trigger: "push back",
        badDrafts: ["đẩy lại", "đẩy lùi"],
        preferred: "phản đối"
    ),
    PhraseRule(
        trigger: "pushback",
        badDrafts: ["đẩy lại", "đẩy lùi"],
        preferred: "phản đối"
    ),
    PhraseRule(
        trigger: "table this",
        badDrafts: ["đặt cái này lên bàn", "bày cái này lên bàn"],
        preferred: "gác lại"
    ),
    PhraseRule(
        trigger: "sync up",
        badDrafts: ["đồng bộ lên", "đồng bộ hóa"],
        preferred: "họp sync"
    ),
    PhraseRule(
        trigger: "quick sync",
        badDrafts: ["đồng bộ nhanh", "đồng bộ hóa nhanh"],
        preferred: "họp sync nhanh"
    ),
]

private let englishToVietnameseGlossary: [GlossaryEntry] = [
    GlossaryEntry(
        trigger: "ship",
        badDrafts: ["vận chuyển", "chuyển hàng", "giao hàng", "tàu thủy"],
        preferred: "phát hành",
        scenarios: [.standup, .planning, .general, .lecture, .support],
        needsSoftwareCue: true
    ),
    GlossaryEntry(
        trigger: "shipping",
        badDrafts: ["vận chuyển", "đang chuyển hàng"],
        preferred: "đang phát hành",
        scenarios: [.standup, .planning, .general, .lecture, .support],
        needsSoftwareCue: true
    ),
    GlossaryEntry(
        trigger: "blocker",
        badDrafts: ["người chặn", "vật chặn", "kẻ chặn"],
        preferred: "blocker",
        scenarios: nil
    ),
    GlossaryEntry(
        trigger: "owner",
        badDrafts: ["chủ sở hữu", "chủ nhân"],
        preferred: "người phụ trách",
        scenarios: [.standup, .planning, .general, .support, .clientCall]
    ),
    GlossaryEntry(
        trigger: "ticket",
        badDrafts: ["vé", "tấm vé"],
        preferred: "ticket",
        scenarios: [.standup, .planning, .support, .general]
    ),
    GlossaryEntry(
        trigger: "sprint",
        badDrafts: ["chạy nước rút", "nước rút"],
        preferred: "sprint",
        scenarios: [.standup, .planning, .general]
    ),
    GlossaryEntry(
        trigger: "backlog",
        badDrafts: ["tồn đọng", "danh sách tồn đọng", "công việc tồn đọng"],
        preferred: "backlog",
        scenarios: [.standup, .planning, .general]
    ),
    GlossaryEntry(
        trigger: "spike",
        badDrafts: ["gai", "đinh", "đột biến"],
        preferred: "spike",
        scenarios: [.standup, .planning, .general]
    ),
    GlossaryEntry(
        trigger: "deploy",
        badDrafts: ["triển khai quân sự"],
        preferred: "deploy",
        scenarios: [.standup, .planning, .support, .general]
    ),
    GlossaryEntry(
        trigger: "rollback",
        badDrafts: ["cuộn lại", "lăn lại"],
        preferred: "rollback",
        scenarios: [.standup, .support, .general]
    ),
    GlossaryEntry(
        trigger: "stand-up",
        badDrafts: ["đứng lên", "buổi đứng"],
        preferred: "standup",
        scenarios: nil
    ),
    GlossaryEntry(
        trigger: "standup",
        badDrafts: ["đứng lên", "buổi đứng"],
        preferred: "standup",
        scenarios: nil
    ),
    GlossaryEntry(
        trigger: "pr",
        badDrafts: ["quan hệ công chúng", "quan hệ công cộng"],
        preferred: "PR",
        scenarios: [.standup, .planning, .general, .lecture]
    ),
    GlossaryEntry(
        trigger: "pull request",
        badDrafts: ["yêu cầu kéo", "yêu cầu rút"],
        preferred: "pull request",
        scenarios: nil
    ),
    GlossaryEntry(
        trigger: "merge",
        badDrafts: ["hợp nhất", "sáp nhập"],
        preferred: "merge",
        scenarios: [.standup, .planning, .general]
    ),
    GlossaryEntry(
        trigger: "review",
        badDrafts: ["sự đánh giá", "bài đánh giá"],
        preferred: "review",
        scenarios: [.standup, .planning, .general, .interview]
    ),
    GlossaryEntry(
        trigger: "incident",
        badDrafts: ["sự cố tai nạn"],
        preferred: "sự cố",
        scenarios: [.support, .standup, .general]
    ),
    GlossaryEntry(
        trigger: "mitigate",
        badDrafts: ["làm dịu"],
        preferred: "xử lý giảm tác động",
        scenarios: [.support]
    ),
    GlossaryEntry(
        trigger: "outage",
        badDrafts: ["sự mất điện"],
        preferred: "sự cố gián đoạn",
        scenarios: [.support]
    ),
    GlossaryEntry(
        trigger: "promo",
        badDrafts: ["khuyến mãi", "chương trình khuyến mãi"],
        preferred: "promo",
        scenarios: [.oneOnOne, .interview]
    ),
    GlossaryEntry(
        trigger: "level",
        badDrafts: ["mức độ", "cấp độ"],
        preferred: "level",
        scenarios: [.oneOnOne, .interview]
    ),
    GlossaryEntry(
        trigger: "pipeline",
        badDrafts: ["đường ống", "ống dẫn"],
        preferred: "pipeline",
        scenarios: [.sales, .standup, .planning, .general]
    ),
    GlossaryEntry(
        trigger: "close the deal",
        badDrafts: ["đóng thỏa thuận", "đóng cửa thỏa thuận"],
        preferred: "chốt deal",
        scenarios: [.sales]
    ),
]

private let vietnameseToEnglishPhrases: [PhraseRule] = [
    PhraseRule(
        trigger: "chốt",
        badDrafts: ["lock", "lock it", "padlock", "fasten"],
        preferred: "finalize"
    ),
    PhraseRule(
        trigger: "ok anh",
        badDrafts: ["okay older brother", "ok older brother", "okay brother"],
        preferred: "okay"
    ),
    PhraseRule(
        trigger: "ok chị",
        badDrafts: ["okay older sister", "ok older sister", "okay sister"],
        preferred: "okay"
    ),
    PhraseRule(
        trigger: "dạ",
        badDrafts: ["yes sir", "yes ma'am"],
        preferred: "yes"
    ),
    PhraseRule(
        trigger: "em follow",
        badDrafts: ["little sibling follow", "younger sibling follow"],
        preferred: "I'll follow"
    ),
    PhraseRule(
        trigger: "anh review",
        badDrafts: ["older brother review", "brother review"],
        preferred: "please review"
    ),
    PhraseRule(
        trigger: "chị review",
        badDrafts: ["older sister review", "sister review"],
        preferred: "please review"
    ),
    PhraseRule(
        trigger: "kéo vào",
        badDrafts: ["pull into", "drag into"],
        preferred: "loop in"
    ),
    PhraseRule(
        trigger: "bàn lại sau",
        badDrafts: ["discuss the table later"],
        preferred: "circle back later"
    ),
]

private let vietnameseToEnglishGlossary: [GlossaryEntry] = [
    GlossaryEntry(
        trigger: "ticket",
        badDrafts: ["ticket stub", "admission ticket", "fare"],
        preferred: "ticket",
        scenarios: nil
    ),
    GlossaryEntry(
        trigger: "sprint",
        badDrafts: ["dash", "footrace", "short run"],
        preferred: "sprint",
        scenarios: nil
    ),
    GlossaryEntry(
        trigger: "blocker",
        badDrafts: ["blocker man", "fullback"],
        preferred: "blocker",
        scenarios: nil
    ),
]

private func fold(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        .lowercased()
}

private func mentions(_ trigger: String, in foldedSource: String) -> Bool {
    foldedSource.contains(fold(trigger))
}

private let softwareReleaseCues = [
    "checkout", "pull request", " pr ", "deploy", "release", "sprint",
    "merge", "feature", "build", "commit", "hotfix", "bugfix", "fix",
]

private func hasSoftwareReleaseCue(_ foldedSource: String) -> Bool {
    let padded = " \(foldedSource) "
    return softwareReleaseCues.contains { padded.contains($0) }
}

private func replaceCaseInsensitive(_ needle: String, with replacement: String, in text: String) -> String {
    guard !needle.isEmpty, let regex = try? NSRegularExpression(
        pattern: NSRegularExpression.escapedPattern(for: needle),
        options: [.caseInsensitive]
    ) else { return text }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
}
