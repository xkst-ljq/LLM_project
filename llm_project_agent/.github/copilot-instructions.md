# AI Agent Instructions for LLM_Project

> Full rules: `AGENT.md` (English, canonical) / `AGENT.zh.md` (Chinese)

**TL;DR:** Think in English. Respond in Chinese.
DISCUSS mode default (read-only). EDIT only after "开始编辑"/"go edit".
Survey → no hallucination → validate → flutter analyze clean → overflow checklist → 2 failures stop.

**Output: Multi-File SEARCH/REPLACE total patch**
```
--- File: lib/a.dart
<<<<<<< SEARCH
old (verbatim)
=======
new
>>>>>>> REPLACE
--- File: lib/b.dart (new)
<<<<<<< SEARCH
=======
full content
>>>>>>> REPLACE
--- File: lib/old.dart (delete)
```
Patch tool: `tools/patch/apply_patch_multi.html`
Full files to workspace. Chat: Summary → Patch → Paths → Verify.
"贴全文" → paste complete file immediately.

Project anchors: ui_studio_page.dart >2500 LOC, search `_buildPreviewDraggableCard` / `type: 'linker'`, CharacterCard.entries_json = `character_edit_page.dart`, ID = project util, converter = `lib/tools/character_converter/`, pure Dart.

See AGENT.md §1-8.
