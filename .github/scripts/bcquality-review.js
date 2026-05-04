'use strict';

/**
 * BCQuality Code Review — proper agent bootstrapping
 *
 * Implements the BCQuality protocol described in agent-consumption.md:
 *   1. Orchestrator provides task context and a read_file tool
 *   2. Agent's first call is skills/entry.md  → produces a dispatch record
 *   3. Agent invokes each dispatched action skill in turn
 *   4. Agent reads READ and DO on demand (when first needed)
 *   5. Agent reads only the knowledge files it determines are relevant
 *   6. Agent emits findings-report JSON
 *
 * The orchestrator (this script) implements the agentic tool-use loop.
 * No knowledge files or skills are pre-loaded into the prompt.
 */

const fs   = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const GITHUB_TOKEN  = process.env.GITHUB_TOKEN;
const PR_NUMBER     = parseInt(process.env.PR_NUMBER, 10);
const REPO_OWNER    = process.env.REPO_OWNER;
const REPO_NAME     = process.env.REPO_NAME;
const GITHUB_API    = 'https://api.github.com';
const MODELS_API    = 'https://models.inference.ai.azure.com/chat/completions';
const MODEL         = 'openai/gpt-4o';

// ---------------------------------------------------------------------------
// GitHub REST helpers
// ---------------------------------------------------------------------------
function githubHeaders() {
  return {
    'Authorization':        `Bearer ${GITHUB_TOKEN}`,
    'Accept':               'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'Content-Type':         'application/json',
  };
}

async function getPRFiles() {
  const url = `${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/pulls/${PR_NUMBER}/files?per_page=100`;
  const res = await fetch(url, { headers: githubHeaders() });
  if (!res.ok) throw new Error(`GET PR files failed: ${res.status} ${await res.text()}`);
  return res.json();
}

// ---------------------------------------------------------------------------
// File system helpers
// ---------------------------------------------------------------------------
function readFileSafe(filePath) {
  if (!fs.existsSync(filePath)) return '';
  return fs.readFileSync(filePath, 'utf8');
}

/** Recursively find the first file named `name` under `dir`. */
function findFirst(dir, name) {
  if (!fs.existsSync(dir)) return null;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === name) return path.join(dir, entry.name);
    if (entry.isDirectory() && !entry.name.startsWith('.')) {
      const found = findFirst(path.join(dir, entry.name), name);
      if (found) return found;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// read_file tool — the only tool the agent gets
// Sandboxed: only allows reading files within the repo working directory.
// ---------------------------------------------------------------------------
const TOOL_READ_FILE = {
  type: 'function',
  function: {
    name:        'read_file',
    description: 'Read a file from the BCQuality repository by its repo-relative path. ' +
                 'Use this to navigate BCQuality: start with skills/entry.md, then read ' +
                 'dispatched skills, then read READ/DO on demand, then read knowledge files.',
    parameters: {
      type:       'object',
      properties: {
        path: {
          type:        'string',
          description: 'Repo-relative path, e.g. "skills/entry.md" or "microsoft/knowledge/performance/avoid-calcfields-in-loops.md"',
        },
      },
      required: ['path'],
    },
  },
};

/**
 * Execute the read_file tool call.
 * Returns the file content string, or an error message if the file is not found.
 * Rejects paths that escape the repo root (path traversal guard).
 */
function executeReadFile(relPath) {
  // Normalise and sandbox
  const normalised = path.normalize(relPath).replace(/\\/g, '/');
  if (normalised.startsWith('..') || path.isAbsolute(normalised)) {
    return `ERROR: path "${relPath}" is outside the repository root.`;
  }
  const full = path.join(process.cwd(), normalised);
  if (!fs.existsSync(full)) {
    return `ERROR: file not found: ${normalised}`;
  }
  const content = fs.readFileSync(full, 'utf8');
  console.log(`  [tool] read_file("${normalised}") → ${content.length} chars`);
  return content;
}

// ---------------------------------------------------------------------------
// Agentic loop — proper BCQuality bootstrapping
//
// System prompt: minimal — just tells the agent its role and the convention
//   "invoke skills/entry.md first using read_file".
// The agent navigates BCQuality autonomously via the read_file tool.
// Loop terminates when the agent stops calling tools and returns final JSON.
// ---------------------------------------------------------------------------
const SYSTEM_PROMPT = `\
You are a Business Central code review agent consuming the BCQuality knowledge base.

## Your job
Review the AL code changes in the pr-diff and produce a BCQuality findings-report JSON.

## How to proceed — BCQuality bootstrapping protocol
1. Call read_file("skills/entry.md") — this is always your FIRST action.
   Run the entry skill against the task context to get a dispatch record.
2. For each skill in dispatch.dispatch[], call read_file(<skill.path>).
   Execute each skill's four-step pattern (Source → Relevance → Worklist → Action).
3. Call read_file("skills/read.md") and read_file("skills/do.md") when you first need
   the frontmatter matching rules or output contract. Do NOT read them speculatively.
4. Call read_file() for each knowledge file your Worklist step determines is applicable.
   Do NOT read all knowledge files — only the ones relevant to the changed code.
5. When all dispatched skills have been executed, emit the final findings-report JSON
   as your response content (no tool calls). Respond ONLY with valid JSON.

## Rules
- Never pre-load knowledge files. Read only what the skills tell you to read.
- Do not read .al sample files (*.bad.al, *.good.al) — they are examples only.
- Produce valid JSON conforming to the DO output contract when done.`;

async function runAgentLoop(messages) {
  const MAX_TURNS = 40; // safety cap — prevents runaway tool loops
  let turn = 0;

  while (turn < MAX_TURNS) {
    turn++;
    console.log(`  [agent] turn ${turn}`);

    const res = await fetch(MODELS_API, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${GITHUB_TOKEN}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        model:       MODEL,
        messages,
        tools:       [TOOL_READ_FILE],
        tool_choice: 'auto',
        temperature: 0.1,
        max_tokens:  4096,
      }),
    });

    if (!res.ok) {
      throw new Error(`GitHub Models API error ${res.status}: ${await res.text()}`);
    }

    const data    = await res.json();
    const message = data.choices?.[0]?.message;
    if (!message) throw new Error('Empty response from GitHub Models API');

    // Append the assistant turn to the conversation
    messages.push(message);

    const toolCalls = message.tool_calls ?? [];

    if (toolCalls.length === 0) {
      // Agent is done — extract the final JSON findings-report
      const content = message.content ?? '';
      // Strip markdown code fences if the model wraps JSON in ```
      const jsonStr = content.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
      try {
        return JSON.parse(jsonStr);
      } catch {
        throw new Error(`Agent final response is not valid JSON:\n${jsonStr.substring(0, 400)}`);
      }
    }

    // Execute each tool call and feed results back
    for (const tc of toolCalls) {
      const args   = JSON.parse(tc.function.arguments);
      const result = executeReadFile(args.path);
      messages.push({
        role:         'tool',
        tool_call_id: tc.id,
        content:      result,
      });
    }
  }

  throw new Error(`Agent loop exceeded ${MAX_TURNS} turns without producing a final answer.`);
}

// ---------------------------------------------------------------------------
// PR review formatting + posting
// ---------------------------------------------------------------------------
const SEVERITY_EMOJI = { blocker: '🚫', major: '🔴', minor: '🟡', info: 'ℹ️' };

function formatReviewBody(report) {
  const counts = report.summary?.counts ?? {};
  const total  = (counts.blocker ?? 0) + (counts.major ?? 0) + (counts.minor ?? 0) + (counts.info ?? 0);

  let body = `## BCQuality Code Review\n\n`;

  if (total === 0) {
    body += `✅ No issues found (performance · security)\n`;
    return body;
  }

  const summaryParts = [];
  if (counts.blocker) summaryParts.push(`${counts.blocker} blocker`);
  if (counts.major)   summaryParts.push(`${counts.major} major`);
  if (counts.minor)   summaryParts.push(`${counts.minor} minor`);
  if (counts.info)    summaryParts.push(`${counts.info} info`);
  body += `**${total} finding(s):** ${summaryParts.join(', ')}\n\n`;

  // Findings table
  const findings = report.findings ?? [];
  if (findings.length > 0) {
    body += `| Severity | Location | Finding | Knowledge file |\n`;
    body += `|---|---|---|---|\n`;
    for (const f of findings) {
      const emoji = SEVERITY_EMOJI[f.severity] ?? '•';
      const loc   = f.location?.file
        ? `\`${f.location.file}\`${f.location.line ? `:${f.location.line}` : ''}`
        : '—';
      const ref   = f.references?.[0]?.path
        ? `[\`${path.basename(f.references[0].path, '.md')}\`](${f.references[0].path})`
        : '—';
      const msg   = (f.message ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ').substring(0, 150);
      body += `| ${emoji} ${f.severity} | ${loc} | ${msg} | ${ref} |\n`;
    }
  }

  // Sub-skill outcomes (collapsible)
  const subResults = report['sub-results'] ?? [];
  if (subResults.length > 0) {
    body += `\n<details><summary>Sub-skill outcomes</summary>\n\n`;
    for (const sub of subResults) {
      body += `- **${sub.skill?.id}**: \`${sub.outcome}\``;
      if (sub['outcome-reason']) body += ` — ${sub['outcome-reason']}`;
      body += '\n';
    }
    body += `\n</details>\n`;
  }

  return body;
}

function buildInlineComments(findings, alFiles) {
  const comments = [];
  for (const f of findings) {
    if (!f.location?.file || !f.location?.line) continue;
    const prFile = alFiles.find(af =>
      af.filename === f.location.file ||
      af.filename.endsWith(f.location.file) ||
      f.location.file.endsWith(af.filename)
    );
    if (!prFile) continue;

    const refLine = f.references?.[0]?.path
      ? `\n\n📖 [\`${path.basename(f.references[0].path, '.md')}\`](${f.references[0].path})`
      : '';

    comments.push({
      path: prFile.filename,
      line: f.location.line,
      side: 'RIGHT',
      body: `${SEVERITY_EMOJI[f.severity] ?? '•'} **${f.severity.toUpperCase()}** (BCQuality)\n\n${f.message}${refLine}`,
    });
  }
  return comments;
}

async function postReview(report, alFiles) {
  const body     = formatReviewBody(report);
  const findings = report.findings ?? [];
  const comments = buildInlineComments(findings, alFiles);

  const url = `${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/pulls/${PR_NUMBER}/reviews`;

  // Try with inline comments first; fall back to body-only if the API rejects them
  // (GitHub requires diff positions to exist in the current diff)
  for (const payload of [
    { body, event: 'COMMENT', ...(comments.length ? { comments } : {}) },
    { body, event: 'COMMENT' },
  ]) {
    const res = await fetch(url, {
      method: 'POST',
      headers: githubHeaders(),
      body: JSON.stringify(payload),
    });
    if (res.ok) {
      console.log(`✅ Posted BCQuality review: ${findings.length} finding(s)`);
      return;
    }
    if (payload.comments) {
      console.log(`Inline comments rejected (${res.status}), retrying without them…`);
      continue;
    }
    throw new Error(`Failed to post PR review: ${res.status} ${await res.text()}`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log(`BCQuality review — PR #${PR_NUMBER} in ${REPO_OWNER}/${REPO_NAME}`);

  // 1. Get changed AL files from the PR
  const allFiles = await getPRFiles();
  const alFiles  = allFiles.filter(f =>
    f.filename.endsWith('.al') &&
    f.status !== 'removed' &&
    f.patch
  );

  if (alFiles.length === 0) {
    console.log('No AL changes in this PR — skipping BCQuality review.');
    return;
  }
  console.log(`Changed AL files: ${alFiles.map(f => f.filename).join(', ')}`);

  // 2. Load app.json for task context dimensions (bc-version, countries)
  let appJson = null;
  try {
    const appJsonPath = findFirst('.', 'app.json');
    if (appJsonPath) appJson = JSON.parse(fs.readFileSync(appJsonPath, 'utf8'));
  } catch { /* non-fatal */ }

  const bcVersion = appJson?.application
    ? parseInt(appJson.application.split('.')[0], 10)
    : 28;
  const countries = appJson?.country ? [appJson.country] : ['w1'];

  // 3. Build the task context and pr-diff for the user message
  const taskContext = {
    goal:               'AL code review for pull request',
    'inputs-available': ['pr-diff'],
    technologies:       ['al'],
    'bc-version':       bcVersion,
    countries,
    'application-area': ['all'],
    'enabled-layers':   ['microsoft', 'community', 'custom'],
    'disabled-skills':  [],
  };

  const diffSection = alFiles
    .map(f => `### File: ${f.filename}\n\`\`\`diff\n${f.patch}\n\`\`\``)
    .join('\n\n');

  const userMessage = `Task context:
${JSON.stringify(taskContext, null, 2)}

## Changed AL files (pr-diff)
${diffSection}

Start by reading skills/entry.md using the read_file tool.`;

  // 4. Run the agentic loop — agent navigates BCQuality from skills/entry.md
  console.log(`Starting BCQuality agent loop (${MODEL})…`);
  let report;
  try {
    report = await runAgentLoop([
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user',   content: userMessage   },
    ]);
  } catch (err) {
    console.error(`BCQuality agent loop failed: ${err.message}`);
    // Do not fail the build — AI review is advisory
    process.exit(0);
  }

  // 5. Post the findings as a PR review comment
  await postReview(report, alFiles);
}

main().catch(err => {
  console.error(`BCQuality review error: ${err.message}`);
  process.exit(1);
});
