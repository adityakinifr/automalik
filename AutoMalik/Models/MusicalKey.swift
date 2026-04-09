import Foundation

enum NoteName: Int, CaseIterable, Identifiable {
    case C = 0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .C: return "C"
        case .Cs: return "C#"
        case .D: return "D"
        case .Ds: return "D#"
        case .E: return "E"
        case .F: return "F"
        case .Fs: return "F#"
        case .G: return "G"
        case .Gs: return "G#"
        case .A: return "A"
        case .As: return "A#"
        case .B: return "B"
        }
    }
}

enum ScaleType: String, CaseIterable, Identifiable {
    case major = "Major"
    case minor = "Minor"
    case chromatic = "Chromatic"
    case pentatonicMajor = "Pentatonic Major"
    case pentatonicMinor = "Pentatonic Minor"
    case dorian = "Dorian"
    case mixolydian = "Mixolydian"

    var id: String { rawValue }

    /// Semitone intervals from root
    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        case .chromatic: return Array(0...11)
        case .pentatonicMajor: return [0, 2, 4, 7, 9]
        case .pentatonicMinor: return [0, 3, 5, 7, 10]
        case .dorian: return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian: return [0, 2, 4, 5, 7, 9, 10]
        }
    }
}

struct MusicalKey: Equatable {
    var root: NoteName
    var scale: ScaleType

    /// Returns all valid semitone classes (0-11) for this key
    var validSemitones: Set<Int> {
        Set(scale.intervals.map { ($0 + root.rawValue) % 12 })
    }

    /// Given a frequency, returns the nearest valid note frequency in this key
    func nearestValidFrequency(_ freq: Float) -> Float {
        guard freq > 0 else { return freq }

        let midiNote = 69.0 + 12.0 * log2(Double(freq) / 440.0)
        let semitone = Int(round(midiNote)) % 12
        let normalizedSemitone = semitone < 0 ? semitone + 12 : semitone
        let octaveBase = Int(round(midiNote)) - normalizedSemitone

        // Find nearest valid semitone
        var bestDistance = Int.max
        var bestSemitone = normalizedSemitone
        for valid in validSemitones {
            let dist = min(abs(valid - normalizedSemitone), 12 - abs(valid - normalizedSemitone))
            if dist < bestDistance {
                bestDistance = dist
                bestSemitone = valid
            }
        }

        let targetMidi = Double(octaveBase + bestSemitone)
        return Float(440.0 * pow(2.0, (targetMidi - 69.0) / 12.0))
    }

    /// Returns the note name for a given frequency
    static func noteName(for freq: Float) -> String {
        guard freq > 0 else { return "-" }
        let midiNote = 69.0 + 12.0 * log2(Double(freq) / 440.0)
        let semitone = Int(round(midiNote)) % 12
        let normalized = semitone < 0 ? semitone + 12 : semitone
        let octave = Int(round(midiNote)) / 12 - 1
        let name = NoteName(rawValue: normalized)?.displayName ?? "?"
        return "\(name)\(octave)"
    }
}
