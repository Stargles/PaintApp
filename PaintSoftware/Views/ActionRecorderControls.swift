import SwiftUI

/// The Actions-menu section that drives `ActionRecorder`: start/stop, a live event count, and the
/// list of past recordings with Share and Delete.
///
/// Modelled on `PerfHUD`'s precedent — discreet, default OFF, and nothing runs while it is off (see
/// `ActionRecorder.isCapturing` for the exhaustive statement of what that means on the drawing
/// path). It lives in the Actions menu because that is already where this app's debugging switches
/// go: the pencil-only toggle is three rows above it.
///
/// **Why the button says what it does.** The row is phrased as the state the owner is choosing —
/// "Record My Actions" / "Stop Recording" — rather than as a toggle labelled with the flag it sets,
/// for the same reason the pencil-only row is phrased "Fingers Can Paint": a toggle whose label names
/// an internal is read backwards half the time.
struct ActionRecorderSection: View {
    @ObservedObject var canvasManager: CanvasManager
    @ObservedObject private var recorder = ActionRecorder.shared
    @State private var showRecordings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            recordButton

            if recorder.isRecording {
                liveReadout
            }

            if let problem = recorder.problem {
                Text(problem)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("recorder.problem")
            }

            disclosureRow

            if showRecordings {
                if recorder.recordings.isEmpty {
                    Text("No recordings yet.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                } else {
                    ForEach(recorder.recordings) { recording in
                        recordingRow(recording)
                    }
                }
            }
        }
        .onAppear { recorder.refreshRecordings() }
    }

    private var recordButton: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
                showRecordings = true
            } else {
                recorder.start(canvasSize: canvasManager.canvasSize, projectName: canvasManager.projectName)
            }
        } label: {
            HStack {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .frame(width: 24)
                    .foregroundColor(recorder.isRecording ? .red : .white)
                Text(recorder.isRecording ? "Stop Recording" : "Record My Actions")
                Spacer()
                if recorder.isRecording {
                    // The dot in the menu is a second, redundant "it is on" — the first is the
                    // always-visible badge on the canvas (`ActionRecorderIndicator`). Redundant on
                    // purpose: a recorder the owner forgets is running writes a hundred megabytes of
                    // nothing and buries the four seconds that mattered.
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("recorder.toggle")
        .accessibilityLabel(recorder.isRecording ? "Stop recording actions" : "Record my actions")
    }

    private var liveReadout: some View {
        HStack {
            Image(systemName: "waveform").frame(width: 24).foregroundColor(.red)
            Text("\(recorder.eventCount) events")
            Spacer()
            Text(String(format: "%.0fs", recorder.elapsed))
                .foregroundColor(.gray)
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundColor(.white)
        .padding(.horizontal)
        .padding(.bottom, 6)
        .accessibilityIdentifier("recorder.liveReadout")
        .accessibilityValue("\(recorder.eventCount)")
    }

    private var disclosureRow: some View {
        Button {
            showRecordings.toggle()
            if showRecordings { recorder.refreshRecordings() }
        } label: {
            HStack {
                Image(systemName: "tray.full").frame(width: 24)
                Text("Recordings")
                Spacer()
                Text("\(recorder.recordings.count)").foregroundColor(.gray)
                Image(systemName: showRecordings ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("recorder.recordingsDisclosure")
    }

    private func recordingRow(_ recording: ActionRecorder.Recording) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(recording.name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(recording.sizeText)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer(minLength: 4)
            // The share sheet is the fallback route off the device: AirDrop, Mail, Files. The cable
            // route (`xcrun devicectl device copy from`) is the one an agent uses and needs no
            // interaction at all, but it needs the Mac — this is what makes the recording escape a
            // device that is only on Wi-Fi.
            ShareLink(item: recording.url) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 28, height: 28)
                    .foregroundColor(.blue)
            }
            .accessibilityIdentifier("recorder.share")

            Button {
                recorder.delete(recording)
            } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .foregroundColor(.red.opacity(0.8))
            }
            .accessibilityIdentifier("recorder.delete")
        }
        .foregroundColor(.white)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

/// The always-visible "you are being recorded" badge.
///
/// Sits over the canvas next to the perf HUD and renders **nothing at all** unless a recording is
/// live, so it costs one `if` in `DrawingView`'s body when off. `allowsHitTesting(false)`: it must
/// never eat a touch, least of all during the repro it is announcing — a badge that swallowed the
/// tap the owner was trying to record would be the worst possible bug for this feature to have.
struct ActionRecorderIndicator: View {
    @ObservedObject private var recorder = ActionRecorder.shared

    var body: some View {
        if recorder.isRecording {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("REC \(recorder.eventCount)")
                    .font(.system(.caption2, design: .monospaced).bold())
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.65))
            .clipShape(Capsule())
            .allowsHitTesting(false)
            .accessibilityIdentifier("recorder.indicator")
            .accessibilityValue("\(recorder.eventCount)")
        }
    }
}
