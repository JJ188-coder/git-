import Speech

@available(macOS 26.0, *)
public enum SpeechAnalysisContextFactory {
    public static func make(vocabulary: [String]) -> AnalysisContext {
        let context = AnalysisContext()
        let normalizedVocabulary = VocabularyNormalizer.normalized(vocabulary)
        if !normalizedVocabulary.isEmpty {
            context.contextualStrings[.general] = normalizedVocabulary
        }
        return context
    }
}
