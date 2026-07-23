import SwiftData

public extension ModelContainer {
    static func makeWakemeContainer() throws -> ModelContainer {
        let schema = Schema([
            CalibrationData.self,
            SleepAttackEvent.self,
            SignalSnapshot.self,
            MonitoringSession.self,
            ModelVersion.self,
            FalseNegativeReport.self,
            DrivingDrowsinessSample.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory container for use in unit tests and SwiftUI previews
    static func makeWakemePreviewContainer() throws -> ModelContainer {
        let schema = Schema([
            CalibrationData.self,
            SleepAttackEvent.self,
            SignalSnapshot.self,
            MonitoringSession.self,
            ModelVersion.self,
            FalseNegativeReport.self,
            DrivingDrowsinessSample.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
