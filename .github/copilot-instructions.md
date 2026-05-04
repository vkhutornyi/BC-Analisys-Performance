# PartnerCore AL Development

> MCP v1.4.1 | 13 Native Tools | 556 KB Articles
>
> **Setup:** Install PartnerCore extension, set API key via `Ctrl+Shift+P` → "PartnerCore: Set API Key"

## Available Tools

PartnerCore registers 13 native tools in VS Code. Use them by name — no action parameter needed.

### Planning

| Tool | What it does |
|------|-------------|
| `partnercore_plan_objects` | Plan multiple objects at once — returns IDs, paths, namespaces, starter code. Call FIRST. |
| `partnercore_next_id` | Allocate next available object ID for a type. Use `partnercore_plan_objects` for 2+ objects. |

### Validation (run after writing AL code)

| Tool | What it does |
|------|-------------|
| `partnercore_validate` | 21-rule offline static validation — DataClassification, ApplicationArea, ToolTip, Labels, AppSource, GDPR. Works on single file or whole workspace. |
| `partnercore_diagnostics_ws` | AL compiler diagnostics for all workspace files — real compiler errors and warnings |
| `partnercore_preflight` | Final "am I done?" check — IDs, permissions, prefix, missing properties |
| `partnercore_fix_using` | Auto-inject missing `using` namespace directives into AL files |

### Code Intelligence

| Tool | What it does |
|------|-------------|
| `partnercore_code_review` | Deep AI code review against 180+ AL patterns. Pass file path. |
| `partnercore_performance_scan` | Sub-second scan for 12 performance anti-patterns. Pass file path. |
| `partnercore_knowledge_search` | Search 492 BC knowledge base articles. Pass query string. |
| `partnercore_knowledge_get` | Fetch a specific KB article by path (faster than search). |
| `partnercore_read_source` | Read decompiled BC base app source code. |
| `partnercore_dependencies` | File-level dependency graph — what depends on what. |

### Microsoft AL Tools (always available)

| Tool | What it does |
|------|-------------|
| `al_build` | Build .app package |
| `al_publish` | Publish to BC |
| `al_downloadsymbols` | Download symbol packages |
| `al_get_diagnostics` | Compiler diagnostics |
| `al_symbolsearch` | Search symbols across project |

## Workflow

Every AL task follows this sequence:

### 1. Plan

```
partnercore_plan_objects({
  objects: [
    { type: "table", name: "Cash Flow Entry", module: "CashFlow" },
    { type: "page", name: "Cash Flow Entries", module: "CashFlow" }
  ]
})
```

Returns IDs, file paths, namespaces, starter code. Never hardcode object IDs.

### 2. Learn (before writing)

Fetch the checklist for the object type you're creating:

```
partnercore_knowledge_get({ article: "standards/al-table-review-checklist.md" })
```

| Object type | Checklist |
|------------|-----------|
| Tables | `standards/al-table-review-checklist.md` |
| Pages | `standards/al-page-review-checklist.md` |
| Codeunits | `standards/al-codeunit-review-checklist.md` |
| Enums | `standards/al-enum-review-checklist.md` |
| Reports | `standards/al-report-review-checklist.md` |
| Permission Sets | `standards/al-permissionset-review-checklist.md` |
| Testing | `standards/al-testing.md` |
| Performance | `guides/performance/al-performance-optimization-guide.md` |
| AppSource | `standards/al-appsource-compliance.md` |
| Labels | `standards/al-labels-not-hardcoded-strings.md` |

Or search: `partnercore_knowledge_search({ query: "SetLoadFields best practices" })`

### 3. Write

Use your built-in file tools (edit, create) to write AL code. This is faster than any code generation tool.

### 4. Validate (REQUIRED — all three steps)

```
partnercore_validate({})                              // static analysis (21 rules)
partnercore_diagnostics_ws({})                        // AL compiler errors
partnercore_preflight({})                             // final checklist
```

For deeper review: `partnercore_code_review({ file: "src/MyTable.al" })`
For performance: `partnercore_performance_scan({ file: "src/MyTable.al" })`
Fix namespaces: `partnercore_fix_using({ workspace: true })`

## DO NOT

1. **DO NOT hardcode object IDs** — always use `partnercore_plan_objects` or `partnercore_next_id`
2. **DO NOT use hardcoded strings in Error/Message/Confirm** — use `Label` variables (AppSource rule AA0470). Caption/ToolTip are auto-extracted, no Label needed there.
3. **DO NOT skip validation** — run `partnercore_diagnostics_ws` after writing files
4. **DO NOT read files from internal system paths** — AppData, chat-session-resources, workspaceStorage
5. **DO NOT reuse namespaces** — each object gets its own namespace from `partnercore_plan_objects`

## Labels (Localization — MANDATORY)

```al
// WRONG — hardcoded string, fails AA0470
Error('From Date cannot be blank.');

// CORRECT — Label variable
var
    FromDateBlankErr: Label 'From Date cannot be blank.';
begin
    Error(FromDateBlankErr);
```

## Modules and Namespaces

Module = functional area (Setup, CashFlow, Alerts), NOT object type (Tables, Pages).
Formula: `{Publisher}.{AppName}.{Module}`

Different objects can have different namespaces even in the same folder. Always get the namespace from `partnercore_plan_objects`.

## Multi-Root Workspaces

When VS Code has 2+ folders open, tools operate on the folder containing `app.json`. If multiple `app.json` exist, specify the target folder in tool parameters.

## Tools Not Available?

If a tool call fails or tools are not registered:

1. Reload VS Code (`Ctrl+Shift+P` → "Developer: Reload Window"), then start a **new** chat session
2. Verify extension is enabled: `Ctrl+Shift+P` → "PartnerCore: Set API Key"
3. **NEVER silently fall back** — code without PartnerCore tools has 10-30 compiler errors per file

## Agents

| Agent | Use when |
|-------|----------|
| **@partnercore** | Single-object tasks: create, review, fix |
| **@partnercore-conductor** | Multi-file features: batch create, TDD cycles |
| **@partnercore-architect** | Design tasks: specs, architecture, AppSource strategy |

<!-- partnercore-version: 1.5.0 -->
