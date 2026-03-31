# Source Mapping

This project ports the translation core from `third_party/read-frog` into a macOS menu bar app.

## Direct Reference Sources

- `third_party/read-frog/src/types/config/provider.ts`
- `third_party/read-frog/src/types/config/translate.ts`
- `third_party/read-frog/src/utils/constants/feature-providers.ts`
- `third_party/read-frog/src/utils/request/request-queue.ts`
- `third_party/read-frog/src/utils/request/batch-queue.ts`
- `third_party/read-frog/src/utils/host/translate/translate-text.ts`
- `third_party/read-frog/src/utils/host/translate/execute-translate.ts`
- `third_party/read-frog/src/utils/host/translate/translate-variants.ts`
- `third_party/read-frog/src/entrypoints/background/translation-queues.ts`
- `third_party/read-frog/src/utils/host/translate/api/google.ts`
- `third_party/read-frog/src/utils/host/translate/api/microsoft.ts`
- `third_party/read-frog/src/utils/host/translate/api/ai.ts`

## Port Strategy

- `direct port`
  - provider classification
  - feature-to-provider binding
  - request queue semantics
  - batch queue semantics
  - translation hash construction
  - cache-first translation execution
  - Google / Microsoft / DeepL / DeepLX request semantics
- `semantic rewrite`
  - browser message bus -> local Swift service calls
  - Dexie stores -> SQLite repositories
  - browser extension settings -> UserDefaults + Keychain
  - page/content translation variants -> clipboard translation variants
  - Vercel AI SDK model resolution -> Swift LLM provider adapters
- `not ported`
  - DOM walker
  - page node wrapping / translation-only / bilingual DOM injection
  - browser background entrypoints and content script runtime
  - popup / options UI from read-frog
