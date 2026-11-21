import Foundation
import MetricKit

/// **The app's own crashes and hangs, with stacks, from the system.** MetricKit hands over diagnostic
/// payloads (crash, hang, CPU and disk-write exceptions) on a later launch; each is written as one line of
/// JSON to `Recordings/metrickit-<date>-<UUID>.jsonl`, beside the flight dumps, so Settings lists it with
/// Share and Delete and `tools/pull-ipad-crashes.sh` finds it. Metric (usage) payloads are not kept.
///
/// A backboardd Jetsam never appears here — it is not this process's crash — which is what
/// `UncleanExitWatch` is for.
final class DiagnosticPayloadSink: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticPayloadSink()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        UncleanExitWatch.queue.async {
            for payload in payloads {
                Self.write(json: payload.jsonRepresentation(), into: ActionRecorder.directory,
                           at: payload.timeStampEnd)
            }
            DispatchQueue.main.async { ActionRecorder.shared.refreshRecordings() }
        }
    }

    /// The payload's JSON re-serialised onto one line, so the file is valid JSONL like its neighbours.
    @discardableResult
    static func write(json: Data, into directory: URL, at date: Date) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: json),
              let line = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(ActionRecorder.recordingFilename(prefix: "metrickit", at: date))
        do { try (line + Data("\n".utf8)).write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}
