//
//  QuestionGenerator.swift
//  Elephant Challenge: Math Memory
//
//  Turns a chosen level into a validated question. A selected level always
//  mixes questions from that level AND every level below it, leaning toward the
//  top of the range so the hardest available difficulty keeps showing up.
//
//  The arithmetic rules are ported from Jumping Fox's QuestionEngine: the
//  distractors are the near-misses children actually produce, never values
//  plucked at random.
//

import Foundation

public final class QuestionGenerator {
    public let level: MathLevel
    private let random: RandomSource

    /// Last prompt handed out, so the same sum never appears twice in a row.
    private var lastPrompt: String?
    /// Last operation handed out, so a mixed level does not serve four
    /// multiplications in a row.
    private var lastKind: QuestionKind?
    /// Sub-levels used recently, so the same level does not dominate.
    private var recentSourceLevels: [Int] = []

    /// Which operations a Supermix level draws from. Ignored by every other
    /// topic, which has exactly one operation by definition.
    private let mixedVariant: MixedVariant

    public init(level: MathLevel,
                mixedVariant: MixedVariant = .all,
                random: RandomSource = RandomSource()) {
        self.level = level
        self.mixedVariant = mixedVariant
        self.random = random
    }

    // MARK: - Public API

    /// A question for a normal round.
    /// - Parameter requiredDistractors: how many wrong answers the current card
    ///   mode needs. The generator keeps trying until it can supply that many.
    public func next(requiredDistractors: Int) -> MathQuestion {
        generateValidated(requiredDistractors: requiredDistractors, forceTopLevel: false)
    }

    /// A harder question for the special double card: always drawn from the top
    /// of the available range rather than the weighted mix.
    public func nextHarder(requiredDistractors: Int) -> MathQuestion {
        generateValidated(requiredDistractors: requiredDistractors, forceTopLevel: true)
    }

    /// Resets the anti-repeat memory for a fresh session.
    public func reset() {
        lastPrompt = nil
        lastKind = nil
        recentSourceLevels.removeAll()
    }

    // MARK: - Level mixing

    /// Picks which sub-level this question comes from. The selected level and
    /// every level below it are in play; the top of the range is guaranteed a
    /// minimum share and otherwise weight grows with the level number.
    func pickSourceLevel(forceTop: Bool) -> Int {
        let top = level.index
        guard top > 1, !forceTop else { return top }

        if random.double(in: 0..<1) < GameConfig.topLevelMinimumShare {
            return top
        }

        // Weighted pick over 1...top. Weight of level i is i^exponent.
        let weights = (1...top).map { pow(Double($0), GameConfig.levelWeightExponent) }
        let total = weights.reduce(0, +)
        var threshold = random.double(in: 0..<total)
        for (offset, weight) in weights.enumerated() {
            threshold -= weight
            if threshold < 0 {
                let candidate = offset + 1
                // Nudge away from a level that just came up three times in a
                // row, so the mix keeps moving without ever excluding a level.
                if recentSourceLevels.suffix(3).allSatisfy({ $0 == candidate }), top > 1 {
                    return candidate == top ? max(1, top - 1) : candidate + 1
                }
                return candidate
            }
        }
        return top
    }

    // MARK: - Generation

    private func generateValidated(requiredDistractors: Int, forceTopLevel: Bool) -> MathQuestion {
        // Bounded retry: reject a repeat of the previous prompt, and any
        // question that cannot supply enough genuinely-wrong distractors.
        var fallback: MathQuestion?
        for attempt in 0..<24 {
            let question = generate(forceTopLevel: forceTopLevel,
                                    requiredDistractors: requiredDistractors)
            guard question.isValid(requiredDistractors: requiredDistractors) else { continue }
            fallback = question
            let repeatsPrompt = question.prompt == lastPrompt
            let repeatsKind = question.kind == lastKind
            // Only insist on a different operation for the first few attempts;
            // a single-operation topic has nothing else to offer.
            if repeatsPrompt { continue }
            if repeatsKind, attempt < 3, level.topic == .mixed { continue }
            return record(question)
        }
        // Every retry produced the same prompt (e.g. the table of 1 at card
        // mode 2). Hand back the last valid one rather than an invalid round.
        return record(fallback ?? emergencyQuestion(requiredDistractors: requiredDistractors))
    }

    private func record(_ question: MathQuestion) -> MathQuestion {
        lastPrompt = question.prompt
        lastKind = question.kind
        recentSourceLevels.append(question.sourceLevel)
        if recentSourceLevels.count > 8 { recentSourceLevels.removeFirst() }
        return question
    }

    private func generate(forceTopLevel: Bool, requiredDistractors: Int) -> MathQuestion {
        let source = pickSourceLevel(forceTop: forceTopLevel)
        switch level.topic {
        case .addition: return additionQuestion(source)
        case .subtraction: return subtractionQuestion(source)
        case .tables: return tablesQuestion(source)
        case .fractions: return fractionsQuestion(source)
        case .percentages: return percentagesQuestion(source)
        case .mixed: return mixedQuestion(source)
        }
    }

    /// Last-resort question, used only if every generator attempt failed
    /// validation. Always solvable and always has four distinct distractors.
    private func emergencyQuestion(requiredDistractors: Int) -> MathQuestion {
        let a = random.int(in: 2...9)
        let b = random.int(in: 2...9)
        let answer = a + b
        return MathQuestion(
            prompt: "\(a) + \(b) = ?",
            correctAnswer: "\(answer)",
            distractors: [answer + 1, answer - 1, answer + 2, answer + 3].map(String.init),
            sourceLevel: 1,
            kind: .addition
        )
    }

    // MARK: - Addition

    private func additionQuestion(_ source: Int) -> MathQuestion {
        let add = source
        let ceiling = MathScaling.additionCeiling(source)
        let other = random.int(in: 1...ceiling)
        let answer = add + other
        // Sides swap so the practised number is not always on the left.
        let (a, b) = random.bool() ? (add, other) : (other, add)
        // Real child errors, all close to the answer: counting slips (±1/±2),
        // forgetting to add, and adding the number twice.
        var wrong = [answer + 1, answer - 1, answer + 2, answer - 2, other, answer + add]
        if answer >= 15 { wrong += [answer + 10, answer - 10] }
        return build(prompt: "\(a) + \(b) = ?",
                     answer: answer,
                     wrong: wrong,
                     source: source,
                     kind: .addition)
    }

    // MARK: - Subtraction

    private func subtractionQuestion(_ source: Int) -> MathQuestion {
        let take = source
        let ceiling = MathScaling.subtractionCeiling(source)
        let left = random.int(in: take...max(take, ceiling))
        let answer = left - take
        // Counting slips, forgetting to subtract, and subtracting twice.
        var wrong = [answer + 1, answer - 1, answer + 2, answer - 2, left, answer - take]
        if answer >= 12 { wrong += [answer + 10, answer - 10] }
        if left >= 10, take >= 10, left % 10 < take % 10 {
            // The classic column mistake: smaller digit taken from the larger
            // one per column (52 − 38 → 26 instead of 14).
            wrong.append((left / 10 - take / 10) * 10 + (take % 10 - left % 10))
        }
        return build(prompt: "\(left) − \(take) = ?",
                     answer: answer,
                     wrong: wrong,
                     source: source,
                     kind: .subtraction)
    }

    // MARK: - Tables

    /// Roughly 2% of multiplications become a "× 0 = 0" reminder.
    private static let zeroMultiplyChance = 0.02

    private func tablesQuestion(_ source: Int) -> MathQuestion {
        let table = min(GameConfig.maximumLevel, source)

        if random.double(in: 0..<1) < Self.zeroMultiplyChance {
            let prompt = random.bool() ? "\(table) × 0 = ?" : "0 × \(table) = ?"
            // The tempting mistakes: answering the number itself, or 1.
            return build(prompt: prompt,
                         answer: 0,
                         wrong: [table, 1, table + 1, 2, max(2, table * 2), table * 3],
                         source: source,
                         kind: .multiplication)
        }

        let multiplier = random.int(in: 1...12)
        let answer = table * multiplier
        let (a, b) = random.bool() ? (table, multiplier) : (multiplier, table)
        // Neighbouring multiples in the SAME table and the neighbouring TABLE
        // with the same multiplier — exactly the confusions children have.
        let wrong = [table * (multiplier + 1), table * max(1, multiplier - 1),
                     (table + 1) * multiplier, max(0, table - 1) * multiplier,
                     answer + 1, answer - 1, answer + table, answer + 10]
        return build(prompt: "\(a) × \(b) = ?",
                     answer: answer,
                     wrong: wrong,
                     source: source,
                     kind: .multiplication)
    }

    // MARK: - Fractions

    private func fractionsQuestion(_ source: Int) -> MathQuestion {
        let denominator = source > GameConfig.freeLevelCount
            ? (random.element(MathScaling.premiumFractionDenominators) ?? 4)
            : MathScaling.fractionDenominator(source)

        // Three forms, gated on what the denominator supports.
        var forms: [String] = ["fractionOf", "fractionOf"]
        if denominator <= 5 { forms.append("equivalent") }
        if denominator >= 3, denominator <= 12 { forms += ["addSame", "subSame"] }

        switch random.element(forms) ?? "fractionOf" {
        case "equivalent":
            // "1/4 = ?/12" — the numerator that keeps the fraction equal.
            let scale = random.int(in: 2...3)
            let answer = scale
            return build(prompt: "1/\(denominator) = ?/\(denominator * scale)",
                         answer: answer,
                         wrong: [1, denominator, scale + 1, scale + 2,
                                 denominator * scale, denominator + scale],
                         source: source,
                         kind: .fraction)

        case "addSame":
            let n1 = random.int(in: 1...(denominator - 2))
            let n2 = random.int(in: 1...(denominator - 1 - n1))
            let sum = n1 + n2
            let correct = "\(sum)/\(denominator)"
            // Adding the denominators too, and being one part out.
            let wrong = ["\(sum)/\(denominator * 2)",
                         "\(min(denominator - 1, sum + 1))/\(denominator)",
                         "\(max(1, sum - 1))/\(denominator)",
                         "\(n1)/\(denominator)",
                         "\(n2)/\(denominator)",
                         "\(sum)/\(denominator + 1)"]
            return buildText(prompt: "\(n1)/\(denominator) + \(n2)/\(denominator) = ?",
                             answer: correct,
                             wrong: wrong,
                             source: source,
                             kind: .fraction)

        case "subSame":
            let n1 = random.int(in: 2...(denominator - 1))
            let n2 = random.int(in: 1...(n1 - 1))
            let difference = n1 - n2
            let correct = "\(difference)/\(denominator)"
            let wrong = ["\(difference)/\(max(2, denominator - n2))",
                         "\(min(denominator - 1, difference + 1))/\(denominator)",
                         "\(n1 + n2)/\(denominator)",
                         "\(n2)/\(denominator)",
                         "\(n1)/\(denominator)",
                         "\(difference)/\(denominator + 1)"]
            return buildText(prompt: "\(n1)/\(denominator) − \(n2)/\(denominator) = ?",
                             answer: correct,
                             wrong: wrong,
                             source: source,
                             kind: .fraction)

        default:
            // "3/8 × 40 = ?" — always divide first, so the answer stays whole.
            let factor: Int
            if source > GameConfig.freeLevelCount {
                let target = max(2, MathScaling.premiumCeiling(source) / denominator)
                factor = random.int(in: max(1, target - 2)...(target + 2))
            } else {
                factor = random.int(in: 1...6)
            }
            let whole = denominator * factor
            let unit = whole / denominator
            let numerator = denominator <= 2 ? 1 : random.int(in: 1...(denominator - 1))
            let answer = unit * numerator
            // Forgot to multiply (unit), numerator one off, the complement.
            let wrong = [unit, whole, answer + unit, answer - unit,
                         whole - answer, answer + 1, answer - 1, answer + 10]
            return build(prompt: "\(numerator)/\(denominator) × \(whole) = ?",
                         answer: answer,
                         wrong: wrong,
                         source: source,
                         kind: .fraction)
        }
    }

    // MARK: - Percentages

    private static let percentageFraction: [Int: String] = [
        50: "1/2", 25: "1/4", 75: "3/4", 20: "1/5", 10: "1/10", 5: "1/20",
        80: "4/5", 90: "9/10"
    ]

    /// The smallest whole that makes "p% of whole" a whole number.
    private static func percentageBase(_ p: Int) -> Int {
        max(1, 100 / gcd(100, p))
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

    private func percentagesQuestion(_ source: Int) -> MathQuestion {
        let percentage = source > GameConfig.freeLevelCount
            ? (random.element(MathScaling.premiumPercentages) ?? 25)
            : MathScaling.percentage(source)

        // A friendly percentage occasionally becomes a fraction conversion.
        if let fraction = Self.percentageFraction[percentage],
           random.double(in: 0..<1) < 0.15 {
            let others = MathScaling.percentageLevels
                .filter { $0 != percentage }
                .prefix(12)
                .map { "\($0)%" }
            return buildText(prompt: "\(fraction) = ?",
                             answer: "\(percentage)%",
                             wrong: random.shuffled(Array(others)),
                             source: source,
                             kind: .percentage)
        }

        let base = Self.percentageBase(percentage)
        let factor: Int
        if source > GameConfig.freeLevelCount {
            let target = max(1, MathScaling.premiumCeiling(source) / base)
            factor = random.int(in: max(1, target - 2)...(target + 2))
        } else {
            factor = random.int(in: 1...8)
        }
        let whole = base * factor
        let answer = whole * percentage / 100

        // Neighbouring percentages of the SAME whole (25% vs 50% mix-ups), the
        // complement, and counting slips.
        let neighbours = MathScaling.percentageLevels
            .filter { $0 != percentage && whole * $0 % 100 == 0 }
            .sorted { abs($0 - percentage) < abs($1 - percentage) }
            .prefix(3)
            .map { whole * $0 / 100 }
        let wrong = neighbours + [whole - answer, answer + 1, answer - 1,
                                  answer + 10, answer * 2]
        return build(prompt: "\(percentage)% × \(whole) = ?",
                     answer: answer,
                     wrong: wrong,
                     source: source,
                     kind: .percentage)
    }

    // MARK: - Mixed

    /// Harder operations carry more weight, so a mixed level keeps climbing.
    private static let mixedWeights: [(QuestionKind, Double)] = [
        (.addition, 12), (.subtraction, 16), (.multiplication, 24),
        (.fraction, 22), (.percentage, 26)
    ]

    private func mixedQuestion(_ source: Int) -> MathQuestion {
        // Only the operations the chosen Supermix variant covers are in play.
        let allowed = Self.mixedWeights.filter { kind, _ in
            mixedVariant.topics.contains(kind.topic)
        }
        let pool = allowed.isEmpty ? Self.mixedWeights : allowed
        let total = pool.reduce(0) { $0 + $1.1 }
        var threshold = random.double(in: 0..<total)
        var chosen = pool[0].0
        for (kind, weight) in pool {
            threshold -= weight
            if threshold < 0 { chosen = kind; break }
        }
        switch chosen {
        case .addition: return additionQuestion(source)
        case .subtraction: return subtractionQuestion(source)
        case .multiplication: return tablesQuestion(source)
        case .fraction: return fractionsQuestion(source)
        case .percentage: return percentagesQuestion(source)
        }
    }

    // MARK: - Assembly

    /// Builds a numeric question: drops negatives and duplicates, then pads
    /// with near-miss offsets until there are always enough wrong answers.
    private func build(prompt: String,
                       answer: Int,
                       wrong: [Int],
                       source: Int,
                       kind: QuestionKind) -> MathQuestion {
        var seen: Set<Int> = [answer]
        var distractors: [Int] = []
        for candidate in wrong where candidate >= 0 && !seen.contains(candidate) {
            seen.insert(candidate)
            distractors.append(candidate)
        }
        // Pad with the closest unused offsets, so even a tiny answer like 0
        // still yields four distinct, plausible neighbours.
        var offset = 1
        while distractors.count < 6 && offset < 40 {
            for candidate in [answer + offset, answer - offset] where candidate >= 0 {
                if !seen.contains(candidate) {
                    seen.insert(candidate)
                    distractors.append(candidate)
                }
            }
            offset += 1
        }
        return MathQuestion(prompt: prompt,
                            correctAnswer: "\(answer)",
                            distractors: random.shuffled(distractors).map(String.init),
                            sourceLevel: source,
                            kind: kind)
    }

    /// Builds a question whose answers are text (fractions, percentages).
    private func buildText(prompt: String,
                           answer: String,
                           wrong: [String],
                           source: Int,
                           kind: QuestionKind) -> MathQuestion {
        let correct = AnswerValue(answer)
        var seen: Set<AnswerValue> = [correct]
        var distractors: [String] = []
        for candidate in wrong {
            let value = AnswerValue(candidate)
            guard value != correct, !seen.contains(value) else { continue }
            seen.insert(value)
            distractors.append(candidate)
        }
        // Pad so even a tiny denominator (thirds) can fill a four-card round.
        // Fractions get neighbouring parts and neighbouring denominators;
        // percentages get nearby percentages. Both stay plausible.
        if distractors.count < 4 {
            for candidate in Self.padding(for: answer) {
                guard distractors.count < 6 else { break }
                let value = AnswerValue(candidate)
                guard value != correct, !seen.contains(value) else { continue }
                seen.insert(value)
                distractors.append(candidate)
            }
        }
        return MathQuestion(prompt: prompt,
                            correctAnswer: answer,
                            distractors: random.shuffled(distractors),
                            sourceLevel: source,
                            kind: kind)
    }

    /// Plausible neighbours for a textual answer, used only when the
    /// hand-written near-misses did not yield enough distinct options.
    private static func padding(for answer: String) -> [String] {
        if answer.hasSuffix("%") {
            guard let value = Int(answer.dropLast()) else { return [] }
            return [value + 5, value - 5, value + 10, value - 10, value + 25, value * 2]
                .filter { $0 > 0 && $0 <= 100 && $0 != value }
                .map { "\($0)%" }
        }
        let parts = answer.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let numerator = Int(parts[0]),
              let denominator = Int(parts[1]), denominator > 1 else { return [] }
        var candidates: [String] = []
        for n in 1..<max(2, denominator) where n != numerator {
            candidates.append("\(n)/\(denominator)")
        }
        for d in [denominator + 1, denominator + 2, denominator * 2] {
            candidates.append("\(numerator)/\(d)")
        }
        return candidates
    }
}
