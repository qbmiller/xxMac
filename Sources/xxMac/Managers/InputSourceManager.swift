import Carbon
import Foundation

enum InputSourceManager {
    static func selectEnglishInputSource() {
        let properties = [
            kTISPropertyInputSourceID: "com.apple.keylayout.ABC" as CFString
        ] as CFDictionary

        guard let sources = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else {
            return
        }

        TISSelectInputSource(source)
    }
}
