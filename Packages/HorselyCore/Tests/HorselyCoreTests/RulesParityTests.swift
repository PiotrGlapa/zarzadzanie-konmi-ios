import Foundation
import Testing
@testable import HorselyCore

/// Zgodność reguł z programem 2.0.0 (T053, contracts/rules-parity.md): Pulpit z zegarem z nazwy pliku, oś czasu każdego konia i scenariusze
/// zapisu (stan `before` + żądanie → stan `after` albo ten sam błąd) dla zestawów `maly`, `brzegowy`, `duzy`.
struct RulesParityTests {
    private static let sets = ["maly", "brzegowy", "duzy"]

    private func export(_ set: String) throws -> ExportDocument {
        try ExportDocument.parse(Fixtures.data("parity/\(set)/export.json"))
    }

    private func index(_ set: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Fixtures.data("parity/\(set)/index.json")) as! [String: Any]
    }

    @Test(arguments: sets)
    func theDashboardEqualsTheAnswerOfTheProgram(set: String) throws {
        let source = InMemoryRecordSource(document: try export(set))
        let days = try #require(try index(set)["dashboards"] as? [String])
        #expect(!days.isEmpty)
        for text in days {
            let day = try #require(LocalDate(text))
            let expected = try JSONDecoder().decode(Dashboard.self, from: Fixtures.data("parity/\(set)/dashboard@\(text).json"))
            let actual = try LocalViews(source: source).dashboard(today: day)
            #expect(actual.horses == expected.horses, "\(set) \(text): kafle koni")
            #expect(actual.overdue == expected.overdue, "\(set) \(text): przeterminowane")
            #expect(actual.upcoming == expected.upcoming, "\(set) \(text): nadchodzące")
            #expect(actual.laterThisMonth == expected.laterThisMonth, "\(set) \(text): później w tym miesiącu")
            #expect(actual.recentEntries == expected.recentEntries, "\(set) \(text): ostatnie wpisy")
            #expect(actual.costsThisMonth == expected.costsThisMonth, "\(set) \(text): koszty miesiąca")
            #expect(actual.costsPreviousMonth == expected.costsPreviousMonth, "\(set) \(text): koszty poprzedniego miesiąca")
            #expect(actual.horizonDays == expected.horizonDays)
        }
    }

    private struct TimelineFile: Decodable {
        let items: [TimelineItem]
        let totalCount: Int
    }

    @Test(arguments: sets)
    func theTimelineOfEveryHorseEqualsTheAnswerOfTheProgram(set: String) throws {
        let source = InMemoryRecordSource(document: try export(set))
        let ids = try #require(try index(set)["timelines"] as? [String])
        #expect(!ids.isEmpty)
        for id in ids {
            let expected = try JSONDecoder().decode(TimelineFile.self, from: Fixtures.data("parity/\(set)/timeline/\(id).json"))
            let page = try LocalViews(source: source).timeline(TimelineFilter(horseId: id, pageSize: 200))
            #expect(page.totalCount == expected.totalCount, "\(set) \(id): liczba wpisów")
            #expect(page.items == expected.items, "\(set) \(id): wpisy osi czasu")
        }
    }

    @Test func theEdgeSetCarriesAnInjuredHorseWithItsDashboardTile() throws {
        let document = try export("brzegowy")
        let injured = try #require(document.records(of: .horse).compactMap { $0 as? LocalHorse }.first { $0.status == .injured })
        let dashboard = try JSONDecoder().decode(Dashboard.self, from: Fixtures.data("parity/brzegowy/dashboard@2026-09-28.json"))
        #expect(dashboard.horses.first { $0.horseId == injured.id }?.status == .injured)
        let scenarios = try #require(try index("brzegowy")["scenarios"] as? [String])
        for name in ["kon-status-kontuzjowany", "kon-kontuzjowany-bez-daty-statusu", "kon-status-powrot-na-aktywny", "kon-padly-wraca-jako-kontuzjowany"] {
            #expect(scenarios.contains(name), "brak scenariusza \(name)")
        }
    }
}

/// Scenariusze zapisu wpisów z programu (`parity/brzegowy/scenarios/*.json`): silnik reguł trybu samodzielnego daje ten sam stan końcowy
/// (identyczne rekordy poza `id` nowych rekordów) albo ten sam błąd przy tych samych polach i z tym samym tekstem.
struct RuleScenarioParityTests {
    private static let prefixes = ["notatka-", "start-", "termin-", "trening-", "wizyta-", "zakup-", "zawody-"]

    private struct Scenario {
        let name: String
        let clock: LocalDateTime
        let before: ExportDocument
        let after: ExportDocument?
        let method: String
        let segments: [String]
        let body: Data?
        let ifMatch: Int?
        let status: Int
        let error: [String: Any]
    }

    private func scenarioNames() throws -> [String] {
        let index = try JSONSerialization.jsonObject(with: Fixtures.data("parity/brzegowy/index.json")) as! [String: Any]
        let names = index["scenarios"] as? [String] ?? []
        return names.filter { name in Self.prefixes.contains { name.hasPrefix($0) } }
    }

    private func load(_ name: String) throws -> Scenario {
        let object = try JSONSerialization.jsonObject(with: Fixtures.data("parity/brzegowy/scenarios/\(name).json")) as! [String: Any]
        let operation = object["operation"] as! [String: Any]
        let response = object["response"] as! [String: Any]
        let path = (operation["path"] as! String).replacingOccurrences(of: "/api/v1/", with: "")
        let body = (operation["body"] as? [String: Any]).map { try! JSONSerialization.data(withJSONObject: $0) }
        let after = try (object["after"]).map { try ExportDocument.parse(JSONSerialization.data(withJSONObject: $0)) }
        return Scenario(
            name: name, clock: LocalDateTime(object["clock"] as! String)!, before: try ExportDocument.parse(JSONSerialization.data(withJSONObject: object["before"]!)),
            after: after, method: operation["method"] as! String, segments: path.split(separator: "/").map(String.init), body: body,
            ifMatch: operation["ifMatch"] as? Int, status: response["status"] as! Int, error: object["error"] as? [String: Any] ?? [:]
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, _ scenario: Scenario) throws -> T {
        try JSONDecoder().decode(type, from: scenario.body ?? Data("{}".utf8))
    }

    /// Wykonuje żądanie ze scenariusza na silniku.
    private func perform(_ scenario: Scenario, engine: RuleEngine) throws -> RuleOutcome {
        let s = scenario.segments
        let version = scenario.ifMatch ?? ((try? JSONSerialization.jsonObject(with: scenario.body ?? Data("{}".utf8)) as? [String: Any])?["version"] as? Int)
        switch (scenario.method, s[0]) {
        case ("POST", "reminders") where s.count == 3:
            return engine.reminderAction(id: s[1], s[2] == "complete" ? .complete : .dismiss)
        case ("POST", "competitions") where s.count == 3 && s[2] == "starts":
            return engine.createCompetitionStart(competitionId: s[1], try decode(CompetitionStartInput.self, scenario))
        case ("POST", "vet-visits"): return engine.createVetVisit(try decode(VetVisitInput.self, scenario))
        case ("POST", "farrier-visits"): return engine.createFarrierVisit(try decode(FarrierVisitInput.self, scenario))
        case ("POST", "physio-visits"): return engine.createPhysioVisit(try decode(PhysioVisitInput.self, scenario))
        case ("POST", "specialist-visits"): return engine.createSpecialistVisit(try decode(SpecialistVisitInput.self, scenario))
        case ("POST", "notes"): return engine.createNote(try decode(NoteInput.self, scenario))
        case ("POST", "purchases"): return engine.createPurchase(try decode(PurchaseInput.self, scenario))
        case ("POST", "trainings"): return engine.createTraining(try decode(TrainingInput.self, scenario))
        case ("POST", "competitions"): return engine.createCompetition(try decode(CompetitionInput.self, scenario))
        case ("POST", "reminders"): return engine.createReminder(try decode(ReminderInput.self, scenario))
        case ("PUT", "vet-visits"): return engine.updateVetVisit(id: s[1], try decode(VetVisitInput.self, scenario), expectedVersion: version)
        case ("PUT", "farrier-visits"): return engine.updateFarrierVisit(id: s[1], try decode(FarrierVisitInput.self, scenario), expectedVersion: version)
        case ("PUT", "physio-visits"): return engine.updatePhysioVisit(id: s[1], try decode(PhysioVisitInput.self, scenario), expectedVersion: version)
        case ("PUT", "specialist-visits"): return engine.updateSpecialistVisit(id: s[1], try decode(SpecialistVisitInput.self, scenario), expectedVersion: version)
        case ("PUT", "notes"): return engine.updateNote(id: s[1], try decode(NoteInput.self, scenario), expectedVersion: version)
        case ("PUT", "purchases"): return engine.updatePurchase(id: s[1], try decode(PurchaseInput.self, scenario), expectedVersion: version)
        case ("PUT", "trainings"): return engine.updateTraining(id: s[1], try decode(TrainingInput.self, scenario), expectedVersion: version)
        case ("PUT", "competitions"): return engine.updateCompetition(id: s[1], try decode(CompetitionInput.self, scenario), expectedVersion: version)
        case ("PUT", "reminders"): return engine.updateReminder(id: s[1], try decode(ReminderInput.self, scenario), expectedVersion: version)
        case ("DELETE", let collection):
            let types: [String: RecordType] = ["vet-visits": .vetVisit, "purchases": .purchase, "notes": .note, "trainings": .training, "farrier-visits": .farrierVisit]
            return engine.delete(try #require(types[collection], "nieobsłużona kolekcja \(collection)"), id: s[1])
        default:
            Issue.record("Nieobsłużone żądanie \(scenario.method) \(s.joined(separator: "/"))")
            return .rejected(.notFound(what: "operacja", id: ""))
        }
    }

    // MARK: Stan końcowy

    private func snapshot(_ source: InMemoryRecordSource) throws -> [any LocalRecord] {
        try RecordType.allCases.flatMap { try source.query($0, horseId: nil, from: nil, to: nil, includeDeleted: false).map(\.record) }
    }

    /// Rekordy jako teksty: nowe `id` zastąpione etykietami wg zawartości, leki bez `id` i znaczników czasu, konie zakupu posortowane.
    private func canonical(_ records: [any LocalRecord], knownIds: Set<String>) throws -> [String: [String]] {
        var objects: [(collection: String, object: [String: Any])] = []
        for record in records {
            var object = try JSONSerialization.jsonObject(with: RecordCodec.encode(record)) as! [String: Any]
            if record.recordType == .purchase { object["horseIds"] = (object["horseIds"] as? [String] ?? []).sorted() }
            if record.recordType == .vetVisit {
                let medications = (object["medications"] as? [[String: Any]] ?? []).map { medication -> [String: Any] in
                    var copy = medication
                    copy.removeValue(forKey: "id"); copy.removeValue(forKey: "createdAt"); copy.removeValue(forKey: "updatedAt")
                    return copy
                }.sorted { ($0["sortOrder"] as? Int ?? 0) < ($1["sortOrder"] as? Int ?? 0) }
                object["medications"] = medications
            }
            objects.append((record.recordType.rawValue, object))
        }
        let newIds = Set(objects.compactMap { $0.object["id"] as? String }).subtracting(knownIds)
        func text(_ object: Any) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        }
        func relabel(_ value: Any, _ labels: [String: String]) -> Any {
            switch value {
            case let dictionary as [String: Any]: return dictionary.mapValues { relabel($0, labels) }
            case let array as [Any]: return array.map { relabel($0, labels) }
            case let string as String: return labels[string] ?? string
            default: return value
            }
        }
        var labels: [String: String] = [:]
        let placeholder = Dictionary(uniqueKeysWithValues: newIds.map { ($0, "#") })
        for collection in Set(objects.map(\.collection)) {
            let fresh = objects.filter { $0.collection == collection && newIds.contains($0.object["id"] as? String ?? "") }
            let signatures = fresh.map { entry -> (String, String) in
                var copy = entry.object
                copy.removeValue(forKey: "id"); copy.removeValue(forKey: "createdAt"); copy.removeValue(forKey: "updatedAt")
                return (entry.object["id"] as! String, text(relabel(copy, placeholder)))
            }.sorted { $0.1 < $1.1 }
            for (index, entry) in signatures.enumerated() { labels[entry.0] = "NEW-\(collection)-\(index + 1)" }
        }
        var result: [String: [String]] = [:]
        for entry in objects { result[entry.collection, default: []].append(text(relabel(entry.object, labels))) }
        return result.mapValues { $0.sorted() }
    }

    // MARK: Błąd

    private func compare(problem: RuleProblem, status: Int, error: [String: Any]) -> String? {
        switch problem {
        case let .validation(errors, _):
            guard status == 400 else { return "status \(status), silnik: błąd walidacji" }
            let expected = (error["errors"] as? [String: [String]] ?? [:]).mapValues { $0.sorted() }
            let actual = errors.mapValues { $0.sorted() }
            return expected == actual ? nil : "błędy pól: program \(expected), silnik \(actual)"
        case let .conflict(reason, message):
            if status != 409 { return "status \(status), silnik: konflikt" }
            if error["reason"] as? String != reason.rawValue { return "powód: program \(String(describing: error["reason"])), silnik \(reason.rawValue)" }
            if error["detail"] as? String != message { return "tekst: program „\(String(describing: error["detail"]))”, silnik „\(message)”" }
            return nil
        case .notFound:
            return status == 404 ? nil : "status \(status), silnik: nie znaleziono"
        }
    }

    private func run(_ name: String) throws -> String? {
        let scenario = try load(name)
        let source = InMemoryRecordSource(document: scenario.before)
        var counter = 0
        let engine = RuleEngine(source: source, dates: FixedDateProvider(scenario.clock), newId: {
            counter += 1
            return String(format: "aaaaaaaa-aaaa-aaaa-aaaa-%012d", counter)
        })
        let outcome = try perform(scenario, engine: engine)
        if (200..<300).contains(scenario.status) {
            guard case let .saved(saved) = outcome else { return "program przyjął (status \(scenario.status)), silnik odrzucił: \(String(describing: outcome.problem))" }
            let known = Set(scenario.before.records.map(\.record.id))
            let beforeSnapshot = try canonical(try snapshot(source), knownIds: known)
            _ = beforeSnapshot
            for write in saved.writes {
                source.upsert(SourceRow(record: write.record, dateKey: write.dateKey, isDeleted: write.deletedAt != nil, deletionBatchId: write.deletionBatchId))
            }
            guard let after = scenario.after else { return nil }
            let expected = try canonical(after.records.map(\.record), knownIds: known)
            let actual = try canonical(try snapshot(source), knownIds: known)
            for collection in Set(expected.keys).union(actual.keys).sorted() {
                let left = expected[collection] ?? []
                let right = actual[collection] ?? []
                if left == right { continue }
                let onlyProgram = left.filter { !right.contains($0) }
                let onlyEngine = right.filter { !left.contains($0) }
                return "kolekcja \(collection) (program \(left.count), silnik \(right.count)):\n program: \(onlyProgram.joined(separator: "\n          "))\n silnik:  \(onlyEngine.joined(separator: "\n          "))"
            }
            return nil
        }
        guard case let .rejected(problem) = outcome else { return "program odrzucił (status \(scenario.status)), silnik zapisał" }
        return compare(problem: problem, status: scenario.status, error: scenario.error)
    }

    @Test func everyEntryScenarioGivesTheAnswerOfTheProgram() throws {
        let names = try scenarioNames()
        #expect(names.count >= 25, "scenariuszy wpisów: \(names.count)")
        var failures: [String] = []
        for name in names {
            do {
                if let problem = try run(name) { failures.append("\(name): \(problem)") }
            } catch {
                failures.append("\(name): wyjątek \(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) z \(names.count) scenariuszy:\n" + failures.joined(separator: "\n---\n"))
    }
}
