import XCTest
import Combine
@testable import AIQuotaWidget

final class CursorBillingModeTests: XCTestCase {

    // MARK: - AppSettings Persistence

    func testCursorBillingModePersistence() throws {
        let suiteName = "test.AIQuotaWidget.AppSettings.CursorBillingMode"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create temporary UserDefaults")
            return
        }

        var settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.cursorBillingMode, .auto) // Default should be auto

        settings.cursorBillingMode = .api

        // Re-init settings to see if it retrieves from defaults
        settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.cursorBillingMode, .api)

        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - CursorUsageBasedProvider Parsing Mock

    class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }

        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    func testProviderApiBillingMode() async throws {
        let jsonString = """
        {
            "planUsage": {
                "limit": 20000,
                "remaining": 15000,
                "totalPercentUsed": 25,
                "apiPercentUsed": 10,
                "autoPercentUsed": 40
            },
            "billingCycleEnd": "1700000000000",
            "spendLimitUsage": {
                "used": 100,
                "limit": 1000
            }
        }
        """
        
        let planInfoJson = """
        {
            "planName": "PRO"
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data: Data
            if request.url?.absoluteString.contains("GetCurrentPeriodUsage") == true {
                data = Data(jsonString.utf8)
            } else {
                data = Data(planInfoJson.utf8)
            }
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AuthorizedHTTPClient(accessToken: "test-token", refreshToken: nil, session: session)

        let provider = CursorUsageBasedProvider(
            client: client,
            fallbackPlanName: "PRO",
            billingMode: .api
        )

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.remainingPercent, 90, accuracy: 0.001) // 100 - 10 = 90
        XCTAssertEqual(snapshot.primaryText, "$180.00 left") // 20000 * (1 - 0.10) = 18000 cents = $180
        XCTAssertEqual(snapshot.planName, "PRO")
    }

    func testProviderAutoBillingMode() async throws {
        let jsonString = """
        {
            "planUsage": {
                "limit": 20000,
                "remaining": 15000,
                "totalPercentUsed": 25,
                "apiPercentUsed": 10,
                "autoPercentUsed": 40
            },
            "billingCycleEnd": "1700000000000",
            "spendLimitUsage": {
                "used": 100,
                "limit": 1000
            }
        }
        """
        
        let planInfoJson = """
        {
            "planName": "PRO"
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data: Data
            if request.url?.absoluteString.contains("GetCurrentPeriodUsage") == true {
                data = Data(jsonString.utf8)
            } else {
                data = Data(planInfoJson.utf8)
            }
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AuthorizedHTTPClient(accessToken: "test-token", refreshToken: nil, session: session)

        let provider = CursorUsageBasedProvider(
            client: client,
            fallbackPlanName: "PRO",
            billingMode: .auto
        )

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.remainingPercent, 60, accuracy: 0.001) // 100 - 40 = 60
        XCTAssertEqual(snapshot.primaryText, "$120.00 left") // 20000 * (1 - 0.40) = 12000 cents = $120
    }

    func testProviderFallbackToTotalPercentUsed() async throws {
        let jsonString = """
        {
            "planUsage": {
                "limit": 20000,
                "remaining": 15000,
                "totalPercentUsed": 25
            },
            "billingCycleEnd": "1700000000000",
            "spendLimitUsage": {
                "used": 100,
                "limit": 1000
            }
        }
        """
        
        let planInfoJson = """
        {
            "plan": { "name": "Ultra" }
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data: Data
            if request.url?.absoluteString.contains("GetCurrentPeriodUsage") == true {
                data = Data(jsonString.utf8)
            } else {
                data = Data(planInfoJson.utf8)
            }
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = AuthorizedHTTPClient(accessToken: "test-token", refreshToken: nil, session: session)

        let provider = CursorUsageBasedProvider(
            client: client,
            fallbackPlanName: "PRO",
            billingMode: .api
        )

        let snapshot = try await provider.fetch()

        XCTAssertEqual(snapshot.remainingPercent, 75, accuracy: 0.001) // 100 - 25 = 75
        XCTAssertEqual(snapshot.primaryText, "$150.00 left") // 20000 * (1 - 0.25) = 15000 cents = $150
        XCTAssertEqual(snapshot.planName, "Ultra")
    }

    @MainActor
    func testCollapsedTooltipTextCursor() {
        let settings = AppSettings()
        settings.language = .english
        let service = QuotaService(settings: settings)
        let contentView = ContentView(settings: settings, service: service)
        
        settings.selectedTab = .cursor
        
        // 1. With usage-based state loaded:
        let usageBasedSnapshot = QuotaSnapshot(
            remainingPercent: 80,
            primaryText: "$160.00 left",
            mode: .usageBased,
            ledStatus: .green
        )
        service.setTestState(.loaded(usageBasedSnapshot), for: .cursor)
        
        settings.cursorBillingMode = .auto
        XCTAssertEqual(contentView.collapsedTooltipText, "Cursor (Auto Mode)")
        
        settings.cursorBillingMode = .api
        XCTAssertEqual(contentView.collapsedTooltipText, "Cursor (API Mode)")
        
        // 2. With legacy state loaded:
        let legacySnapshot = QuotaSnapshot(
            remainingPercent: 50,
            primaryText: "250 / 500 requests",
            mode: .legacy,
            ledStatus: .yellow
        )
        service.setTestState(.loaded(legacySnapshot), for: .cursor)
        XCTAssertEqual(contentView.collapsedTooltipText, "Cursor")
    }

    @MainActor
    func testCollapsedTooltipTextCodex() {
        let settings = AppSettings()
        settings.language = .english
        let service = QuotaService(settings: settings)
        let contentView = ContentView(settings: settings, service: service)
        
        settings.selectedTab = .codex
        XCTAssertEqual(contentView.collapsedTooltipText, "Codex")
    }

    @MainActor
    func testCollapsedTooltipTextAntigravity() {
        let settings = AppSettings()
        settings.language = .english
        let service = QuotaService(settings: settings)
        let contentView = ContentView(settings: settings, service: service)
        
        settings.selectedTab = .antigravity
        settings.antigravityDefaultModelId = "gemini-flash"
        
        // 1. Without active model details loaded:
        XCTAssertEqual(contentView.collapsedTooltipText, "Antigravity (gemini-flash)")
        
        // 2. With active model details loaded:
        let snapshot = QuotaSnapshot(
            remainingPercent: 70,
            primaryText: "Gemini Flash · 70%",
            mode: .unknown,
            secondaryWindows: nil,
            antigravityModels: [
                AntigravityModelInfo(id: "gemini-flash", name: "Gemini 3.5 Flash")
            ],
            activeAntigravityModelId: "gemini-flash",
            ledStatus: .green
        )
        service.setTestState(.loaded(snapshot), for: .antigravity)
        XCTAssertEqual(contentView.collapsedTooltipText, "Antigravity (Gemini 3.5 Flash)")
    }
}
