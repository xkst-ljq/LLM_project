# AGENT.md - LLM_Project Agent Operating Rules

> Canonical version: English. Source of truth for all AI coding agents in this repository.
> Chinese reference: `AGENT.zh.md`
> Patch tools: `tools/patch/apply_patch_multi.html` (browser, no install) / `tools/patch/apply_patch_multi.py` (CLI)

## 0. Meta

- **Think in English. Respond in Chinese.**
  - Internal reasoning, variable names, code comments: English
  - User-facing explanations, reports, UI copy: Chinese
  - Code search: English symbol names first, Chinese UI text as fallback
- **Language of this document: English** — do NOT translate at runtime.

---

## 1. Operating Modes

```
[DISCUSS]  default
  ALLOWED:  read_file, grep, bash (read-only), web_search, reasoning
  FORBIDDEN: write_file, edit_file, any file mutation

[EDIT]  only after explicit user signal:
        "开始编辑" / "动手改" / "执行" / "go edit"
  ALLOWED: all tools
  EXIT: MUST return to DISCUSS and deliver Patch + Change Summary
```

Never start editing while the user is still discussing requirements.

---

## 2. Pre-Edit — MUST

### R1. Survey First, Code Later
- Before ANY production code:
  1. Clone/read repo
  2. Read in parallel (3–5 files): data models, existing import/export, real JSON structures
  3. Report in Chinese: "My understanding: …" + "This task delivers X, explicitly does NOT do Y"
- **Zero LOC until survey is complete.**

### R2. No Hallucination
- Any `old_text` / SEARCH block MUST be verbatim copy-paste from the file.
- FORBIDDEN: `$1`, `...`, `// rest unchanged`, `/* keep original */`, any placeholders
- Missing version / reference file? ASK first. NEVER "assume based on description"
- Files >1500 LOC: MUST read target region ±80 lines in chunks. Verify full context.

### R3. Validate Hard Parts First
- File format / binary / third-party mapping → minimal runnable prototype → validate → production.

---

## 3. Edit — MUST

### R4. Flutter / Dart Zero-Defect
- MUST pass: `dart format .` + `flutter analyze --no-fatal-infos` → 0 errors, 0 warnings
- `const` where possible
- NEVER use BuildContext across async gaps without `if (!mounted) return`
- Null safety complete, no unsafe `!`
- No duplicate Keys

### R5. Overflow / Conflict Checklist — run before EVERY edit
- [ ] Layout: Row/Column → Expanded/Flexible, Text `overflow: TextOverflow.ellipsis`, Lists bounded / `shrinkWrap`
- [ ] State: `setState` guarded by `mounted`, never mutate state in `build()`
- [ ] IDs/Keys: use project ID utility, never hand-roll timestamps, no duplicate Keys
- [ ] Responsive: 360px narrow / 1200px wide checked
- [ ] Schema: entries_json / CharacterCard matches `character_edit_page.dart`, do not invent fields

### R6. Tool Discipline
- Locate: `grep -n` → `read_file` exact range → copy old_text verbatim
- Edit: ONE logical change per SEARCH/REPLACE block
- Verify: read back after edit
- Tool fails 2× → STOP, report in Chinese: what failed / observed / needed. NO 3rd blind retry
- Chinese grep = 0 results → switch to English symbol names immediately

---

## 4. Post-Edit Delivery

### R7. Patch-First Delivery

**Default output: Multi-File SEARCH/REPLACE total patch**

1. **Patch format** — single code block containing ALL changed files:
```
--- File: lib/pages/ui_studio_page.dart
<<<<<<< SEARCH
// old code, verbatim from file, 3–5 lines of context minimum
// to make the match unique
=======
 // new code
>>>>>>> REPLACE

--- File: lib/tools/new_helper.dart (new)
<<<<<<< SEARCH
=======
 // full new file content here
>>>>>>> REPLACE

--- File: lib/old_unused.dart (delete)
```
- `--- File: path/to/file` — one entry per file
- `(new)` suffix = create new file, SEARCH body is empty
- `(delete)` suffix = delete file, no SEARCH block needed
- Multiple SEARCH/REPLACE blocks per file allowed, applied top-to-bottom
- `old` text MUST be verbatim copy from the file, with enough context to be unique
- Batch ALL files modified in this task into ONE total patch

2. **Workspace**
   - Full updated files are ALWAYS written to workspace (downloadable)
   - Patch tool available at: `tools/patch/apply_patch_multi.html` / `tools/patch/apply_patch_multi.py`

3. **Chat output order**
   ```
   1. Change Summary (R8)
   2. Total Patch — Multi-File SEARCH/REPLACE block
   3. Workspace file paths
   4. Verification steps
   ```

4. **Full-file fallback**
   - New files < 500 LOC → MAY paste full file directly
   - User says "贴全文" → MUST paste COMPLETE file content immediately, split across messages if >800 lines, warn before truncating
   - Never silently omit content

**Why patch-first:** saves ~90% context tokens vs full-file paste, prevents 6.8 MB chat blow-up, user applies with one-click tool, zero omission risk.

### R8. Change Summary — REQUIRED after every edit
```
本次改动：
- 文件 A: 做了什么，为什么
- 文件 B: 做了什么，为什么
- 新增/删除: ...

如何验证：
1. flutter analyze
2. flutter run -d ...
3. 打开 xx 页面，检查 xx

预期结果：xxx
受影响文件：path/to/a.dart, path/to/b.dart
```

### R9. Layering & Traceability
- Split: `models / parser / mapper` → separate files
- Pure Dart, no Flutter dependency, where possible — testable
- Unsupported fields → downgrade to disabled custom entry, NEVER drop data
- Always output `converted_fields / unsupported_fields` lists
- Provide `toReport() / toPlainText()`

---

## 5. Self-Check — MUST pass before submitting

- [ ] Complete target region read?
- [ ] SEARCH `old_text` verbatim copy-paste? Any placeholders?
- [ ] `flutter analyze` clean? 0 errors / 0 warnings?
- [ ] Overflow/conflict checklist passed?
- [ ] Total patch includes ALL changed files? Paths correct? `(new)` / `(delete)` marked?
- [ ] Change summary + verification steps provided?
- [ ] Workspace files updated?

If any = NO → DO NOT SUBMIT.

---

## 6. LLM_Project Anchors

- `ui_studio_page.dart` > 2500 LOC — before editing: `sed -n '1650,1850p'` confirm linker location
- Atomic / Linker search: `_buildPreviewDraggableCard` / `type: 'linker'` — DO NOT grep Chinese `联动器` / `原子库`
- `CharacterCard.entries_json` schema authoritative in `character_edit_page.dart`
- ID generation: use project ID utility
- Converter: `lib/tools/character_converter/` — keep pure Dart
- Patch tool: `tools/patch/apply_patch_multi.html` (drag project folder + paste patch → download ZIP)

---

## 7. Patch Format Reference

**Modify existing file:**
```
--- File: lib/pages/example.dart
<<<<<<< SEARCH
  final name = data['name'];
  if (name.isEmpty) return;
=======
  final name = (data['name'] ?? '').toString().trim();
  if (name.isEmpty) {
    notes.add('name missing');
    return;
  }
>>>>>>> REPLACE
```

**New file:**
```
--- File: lib/tools/my_helper.dart (new)
<<<<<<< SEARCH
=======
import 'dart:convert';
/// My helper
...
>>>>>>> REPLACE
```

**Delete file:**
```
--- File: lib/old_file.dart (delete)
```

**Multi-block in one file:** stack multiple SEARCH/REPLACE blocks, top-to-bottom order.

**Tips for LLM:**
- Include 3–5 lines of surrounding context in SEARCH to make match unique
- Keep each SEARCH block focused — one logical change
- Batch ALL files from the current task into ONE total patch
- Test: run `flutter analyze` before producing the patch

---

## 8. Failure Reference

`ui_studio_page.dart` incident violated R1,R2,R3,R6,R7: hallucinated `$1ba/$1bb`, truncated 1662/2538 not detected, guessed version 014, 4× blind retry, no report, full-file paste blew up context.

Successful `character_converter (005)` followed ALL rules above: survey → validate → layered pure-Dart → traceable report → patch-sized delivery.

Keep this file at repo root. All agents MUST follow it.
