import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 18.0, *)
struct VoiceNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.note") {
            ControlWidgetButton(action: OpenVoiceNoteIntent()) {
                Label("Нотатка голосом", systemImage: "mic.fill")
            }
        }
        .displayName("Нотатка голосом")
        .description("Одразу починає запис у DaVincit.")
    }
}

@available(iOS 18.0, *)
struct MomentControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.volchuk.para.control.moment") {
            ControlWidgetButton(action: OpenMomentIntent()) {
                Label("Миттєвість", systemImage: "camera.fill")
            }
        }
        .displayName("Миттєвість")
        .description("Фото з підписом для другої половини.")
    }
}
