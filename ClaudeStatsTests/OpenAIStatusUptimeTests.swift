import Foundation
import Testing
@testable import ClaudeStats

@Suite("OpenAIStatusUptime")
struct OpenAIStatusUptimeTests {
    @Test("Parses product groups, impacts, and group uptime")
    func parsesIncidentIOStatusHTML() throws {
        let fetchedAt = Self.dateTime("2026-05-17T12:00:00Z")
        let snapshot = try OpenAIStatusUptimeHTMLParser.parse(Self.statusPageHTML, fetchedAt: fetchedAt)
        let codex = try #require(snapshot.histories[OpenAIStatusGroupCatalog.codexID])

        #expect(snapshot.groupDefinitions.map(\.name) == ["ChatGPT", "Codex"])
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(codex.groupName == "Codex")
        #expect(codex.sourceUptimePercent == 99.95)
        #expect(codex.uptimePercent() == 99.95)
        #expect(codex.days.count == OpenAIStatusUptimeWindow.dayCount)
        #expect(codex.days.last?.date == Self.date("2026-05-17"))

        let degradedDay = try #require(codex.days.first { $0.date == Self.date("2026-05-15") })
        #expect(degradedDay.degradedPerformanceSeconds == 3_600)
        #expect(degradedDay.relatedEvents.first?.name == "Codex stream is disconnecting intermittently")

        let outageDay = try #require(codex.days.first { $0.date == Self.date("2026-05-16") })
        #expect(outageDay.fullOutageSeconds == 7_200)
        #expect(outageDay.hasOutage)
    }

    @Test("Missing impact data fails safely")
    func missingImpactDataFailsSafely() {
        var didThrowExpectedError = false
        do {
            _ = try OpenAIStatusUptimeHTMLParser.parse("<html></html>")
        } catch let error as OpenAIStatusUptimeHTMLParser.ParserError {
            didThrowExpectedError = error == .missingStatusData("component_impacts")
        } catch {
            didThrowExpectedError = false
        }

        #expect(didThrowExpectedError)
    }

    @Test("Uses uptime SVG classes when historical impact data is absent")
    func parsesRenderedUptimeChartStates() throws {
        let fetchedAt = Self.dateTime("2026-05-17T12:00:00Z")
        let snapshot = try OpenAIStatusUptimeHTMLParser.parse(Self.statusPageHTMLWithRenderedCharts, fetchedAt: fetchedAt)
        let codex = try #require(snapshot.histories[OpenAIStatusGroupCatalog.codexID])

        #expect(codex.sourceUptimePercent == 99.96)
        #expect(codex.days.count == OpenAIStatusUptimeWindow.dayCount)
        #expect(codex.days[87].chartSeverity == .operational)
        #expect(codex.days[88].chartSeverity == .degradedPerformance)
        #expect(codex.days[88].hasOutage)
        #expect(codex.days[88].degradedPerformanceSeconds == 0)
        #expect(codex.days[88].barFillHex == "#f8b500")
        #expect(codex.days[89].chartSeverity == .partialOutage)
    }

    @Test("Uptime percent computes when source value is absent")
    func uptimePercentComputesWithoutSource() throws {
        let history = OpenAIStatusUptimeHistory(
            groupID: OpenAIStatusGroupCatalog.codexID,
            groupName: "Codex",
            startDate: nil,
            days: (0..<OpenAIStatusUptimeWindow.dayCount).map { index in
                OpenAIStatusUptimeDay(
                    date: Self.dateByAdding(index, to: "2026-01-01"),
                    degradedPerformanceSeconds: index == 0 ? 3_600 : 0,
                    partialOutageSeconds: 0,
                    fullOutageSeconds: index == 1 ? 7_200 : 0,
                    relatedEvents: []
                )
            },
            sourceUptimePercent: nil
        )

        let percent = try #require(history.uptimePercent())
        let expected = (1 - (10_800.0 / Double(OpenAIStatusUptimeWindow.dayCount * OpenAIStatusUptimeWindow.secondsPerDay))) * 100
        #expect(abs(percent - expected) < 0.0001)
    }

    private static let statusPageHTML = """
    <html>
      <script>
        {"group":{"components":[{"component_id":"\(OpenAIStatusGroupCatalog.conversationsID)","data_available_since":"2021-03-02T02:07:24Z","description":"$undefined","display_uptime":true,"hidden":false,"name":"Conversations"}],"description":"https://chat.openai.com","display_aggregated_uptime":true,"hidden":false,"id":"\(OpenAIStatusGroupCatalog.chatGPTID)","name":"ChatGPT"}}
        {"group":{"components":[{"component_id":"\(OpenAIStatusGroupCatalog.codexWebID)","data_available_since":"2025-05-16T15:26:46Z","description":"$undefined","display_uptime":true,"hidden":false,"name":"Codex Web"},{"component_id":"\(OpenAIStatusGroupCatalog.codexAPIID)","data_available_since":"2026-03-26T22:18:01Z","description":"$undefined","display_uptime":true,"hidden":false,"name":"Codex API"}],"description":"$undefined","display_aggregated_uptime":true,"hidden":false,"id":"\(OpenAIStatusGroupCatalog.codexID)","name":"Codex"}}
        "component_impacts":[
          {"component_id":"\(OpenAIStatusGroupCatalog.codexAPIID)","end_at":"2026-05-15T13:00:00Z","id":"impact-1","start_at":"2026-05-15T12:00:00Z","status":"degraded_performance","status_page_incident_id":"incident-codex-stream"},
          {"component_id":"\(OpenAIStatusGroupCatalog.codexWebID)","end_at":"2026-05-16T02:00:00Z","id":"impact-2","start_at":"2026-05-16T00:00:00Z","status":"full_outage","status_page_incident_id":"incident-codex-web"}
        ],
        "component_uptimes":[
          {"component_id":"\(OpenAIStatusGroupCatalog.codexWebID)","data_available_since":"2025-05-16T15:26:46Z","status_page_component_group_id":"$undefined","uptime":"99.90"},
          {"component_id":"$undefined","data_available_since":"2025-05-16T15:26:46Z","status_page_component_group_id":"\(OpenAIStatusGroupCatalog.codexID)","uptime":"99.95"}
        ],
        "incident_links":[
          {"id":"incident-codex-stream","name":"Codex stream is disconnecting intermittently","permalink":"https://statuspage.incident.io/openai-1/incidents/mc963m7c","published_at":"2026-05-15T12:00:00Z","status":"resolved"},
          {"id":"incident-codex-web","name":"Codex Web outage","permalink":"https://statuspage.incident.io/openai-1/incidents/codex-web","published_at":"2026-05-16T00:00:00Z","status":"resolved"}
        ]
      </script>
    </html>
    """

    private static let statusPageHTMLWithRenderedCharts = """
    <html>
      <section>
        {"group":{"components":[{"component_id":"\(OpenAIStatusGroupCatalog.conversationsID)","data_available_since":"2021-03-02T02:07:24Z","hidden":false,"name":"Conversations"}],"id":"\(OpenAIStatusGroupCatalog.chatGPTID)","name":"ChatGPT"}}
        \(uptimeSVG(classes: ["pillOperational", "pillOperational", "pillDegradedPerformance"]))
      </section>
      <section>
        {"group":{"components":[{"component_id":"\(OpenAIStatusGroupCatalog.codexWebID)","data_available_since":"2025-05-16T15:26:46Z","hidden":false,"name":"Codex Web"},{"component_id":"\(OpenAIStatusGroupCatalog.codexAPIID)","data_available_since":"2026-03-26T22:18:01Z","hidden":false,"name":"Codex API"}],"id":"\(OpenAIStatusGroupCatalog.codexID)","name":"Codex"}}
        \(uptimeSVG(classes: ["pillOperational", "pillDegradedPerformance", "pillPartialOutage"]))
      </section>
      <script>
        "component_impacts":[],
        "component_uptimes":[
          {"component_id":"$undefined","data_available_since":"2021-03-02T02:07:24Z","status_page_component_group_id":"\(OpenAIStatusGroupCatalog.chatGPTID)","uptime":"99.83"},
          {"component_id":"$undefined","data_available_since":"2025-05-16T15:26:46Z","status_page_component_group_id":"\(OpenAIStatusGroupCatalog.codexID)","uptime":"99.96"}
        ],
        "incident_links":[]
      </script>
    </html>
    """

    private static func uptimeSVG(classes: [String]) -> String {
        let rects = classes.enumerated().map { index, className in
            #"<rect x="\#(index * 7)" y="0" width="5" height="16" class="transition UptimeChart-module-scss-module__test__\#(className)"></rect>"#
        }
        .joined()
        return #"<svg width="100%" height="16">\#(rects)</svg>"#
    }

    private static func dateByAdding(_ days: Int, to rawDate: String) -> Date {
        calendar.date(byAdding: .day, value: days, to: date(rawDate)) ?? date(rawDate)
    }

    private static func date(_ rawDate: String) -> Date {
        dayFormatter.date(from: rawDate) ?? Date(timeIntervalSince1970: 0)
    }

    private static func dateTime(_ rawDate: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawDate) ?? Date(timeIntervalSince1970: 0)
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

}
