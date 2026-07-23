import Foundation

/// A fixed-capacity ring buffer of Doubles. Overwrites oldest values once full.
/// Not thread-safe by itself — callers must serialize access.
struct RingBuffer {
    private var storage: [Double]
    private var writeIndex: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        self.storage = [Double]()
        self.storage.reserveCapacity(capacity)
    }

    mutating func append(_ value: Double) {
        if storage.count < capacity {
            storage.append(value)
        } else {
            storage[writeIndex] = value
        }
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    /// Mean of currently held values, or nil if empty.
    var mean: Double? {
        guard !storage.isEmpty else { return nil }
        return storage.reduce(0, +) / Double(storage.count)
    }

    /// The most recently appended value, or nil if empty.
    var last: Double? {
        guard count > 0 else { return nil }
        let lastIndex = (writeIndex - 1 + capacity) % capacity
        // Guard against the pre-fill phase where storage may be shorter than capacity.
        guard lastIndex < storage.count else { return storage.last }
        return storage[lastIndex]
    }

    mutating func reset() {
        storage.removeAll(keepingCapacity: true)
        writeIndex = 0
        count = 0
    }
}

/// Rolling baseline tracker. One reading per second → 300 readings ≈ 5 minutes.
/// Used internally by the sensor managers; deliberately NOT @Observable.
final class BaselineTracker {

    private static let capacity = 300      // 5 minutes at 1 Hz
    private static let minReadings = 30    // 1 minute minimum before "ready"

    private var hrBuffer = RingBuffer(capacity: capacity)
    private var hrvBuffer = RingBuffer(capacity: capacity)
    private var accelBuffer = RingBuffer(capacity: capacity)

    /// Feed one reading. hr and hrv are optional (skipped when nil); accel is always recorded.
    func update(hr: Double?, hrv: Double?, accel: Double) {
        if let hr { hrBuffer.append(hr) }
        if let hrv { hrvBuffer.append(hrv) }
        accelBuffer.append(accel)
    }

    // MARK: - Baselines (mean of buffer, 0 if empty)
    var baselineHR: Double    { hrBuffer.mean ?? 0 }
    var baselineHRV: Double   { hrvBuffer.mean ?? 0 }
    var baselineAccel: Double { accelBuffer.mean ?? 0 }

    // MARK: - Trends (last reading minus baseline; positive = above baseline)
    // Returns 0 when there's no data to compare.
    var hrTrend: Double {
        guard let last = hrBuffer.last, hrBuffer.count > 0 else { return 0 }
        return last - baselineHR
    }
    var hrvTrend: Double {
        guard let last = hrvBuffer.last, hrvBuffer.count > 0 else { return 0 }
        return last - baselineHRV
    }
    var accelTrend: Double {
        guard let last = accelBuffer.last, accelBuffer.count > 0 else { return 0 }
        return last - baselineAccel
    }

    /// True once all three buffers have at least one minute of data.
    /// NOTE: because hr/hrv can be nil while accel is always present, the HR/HRV buffers
    /// fill more slowly — so readiness is effectively gated on HR data flowing. This is intended.
    var hasEnoughData: Bool {
        hrBuffer.count >= Self.minReadings
            && hrvBuffer.count >= Self.minReadings
            && accelBuffer.count >= Self.minReadings
    }

    /// A looser readiness check for motion-only operation (when HealthKit HR is unavailable).
    /// Motion baseline seeding (Step 2.4) can use this instead of the strict hasEnoughData.
    var hasEnoughMotionData: Bool {
        accelBuffer.count >= Self.minReadings
    }

    func reset() {
        hrBuffer.reset()
        hrvBuffer.reset()
        accelBuffer.reset()
    }
}
