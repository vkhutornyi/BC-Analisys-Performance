'use strict';

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

/** Load every *.md file from a list of directories (non-recursive). */
function loadKnowledgeFiles(dirs) {
  const files = [];
  for (const dir of dirs) {
    if (!fs.existsSync(dir)) continue;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.md')) {
        const fullPath = path.join(dir, entry.name).replace(/\\/g, '/');
        files.push({ path: fullPath, content: fs.readFileSync(fullPath, 'utf8') });
      }
    }
  }
  return files;
}

// ---------------------------------------------------------------------------
// Prompt builders
// ---------------------------------------------------------------------------
function buildSystemPrompt(knowledgeFiles) {
  const doMd       = readFileSafe('skills/do.md');
  const readMd     = readFileSafe('skills/read.md');
  const perfSkill  = readFileSafe('microsoft/skills/review/al-performance-review.md');
  const secSkill   = readFileSafe('microsoft/skills/review/al-security-review.md');

  const knowledgeSection = knowledgeFiles
    .map(kf => `### ${kf.path}\n${kf.content}`)
    .join('\n\n---\n\n');

  return `You are a Business Central AL code reviewer using the BCQuality knowledge base.

## DO meta-skill — output contract
${doMd}

## READ meta-skill — how to read knowledge files
${readMd}

## AL Performance Review skill
${perfSkill}

## AL Security Review skill
${secSkill}

## BCQuality knowledge files
${knowledgeSection}

---
IMPORTANT: Respond with ONLY a single valid JSON object.
Produce a super-skill findings-report (as defined by the DO contract) that combines the results
of running both al-performance-review and al-security-review against the supplied pr-diff.
Do not include any text outside the JSON object.`;
}

function buildUserPrompt(alFiles, appJson) {
  const bcVersion = appJson?.application
    ? parseInt(appJson.application.split('.')[0], 10)
    : 28;
  const countries = appJson?.country ? [appJson.country] : ['w1'];

  const taskContext = {
    goal:              'AL code review for pull request',
    'inputs-available': ['pr-diff'],
    technologies:      ['al'],
    'bc-version':      bcVersion,
    countries,
    'enabled-layers':  ['microsoft', 'community', 'custom'],
  };

  const diffSection = alFiles
    .map(f => `### File: ${f.filename}\n\`\`\`diff\n${f.patch || '(binary or empty)'}\n\`\`\``)
    .join('\n\n');

  return `Task context:
${JSON.stringify(taskContext, null, 2)}

## Changed AL files (pr-diff)
${diffSection}

Review these changes against the BCQuality knowledge base following the AL Performance Review and
AL Security Review skills. Return only the findings-report JSON.`;
}

// ---------------------------------------------------------------------------
// GitHub Models API
// ---------------------------------------------------------------------------
async function callModels(systemPrompt, userPrompt) {
  const res = await fetch(MODELS_API, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${GITHUB_TOKEN}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      model:           MODEL,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user',   content: userPrompt   },
      ],
      response_format: { type: 'json_object' },
      temperature:     0.1,
      max_tokens:      4096,
    }),
  });

  if (!res.ok) {
    throw new Error(`GitHub Models API error ${res.status}: ${await res.text()}`);
  }

  const data    = await res.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error('Empty response from GitHub Models API');

  try {
    return JSON.parse(content);
  } catch {
    throw new Error(`Models response is not valid JSON:\n${content.substring(0, 300)}`);
  }
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

  // 1. Get changed AL files
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

  // 2. Load app.json for task context
  let appJson = null;
  try {
    const appJsonPath = findFirst('.', 'app.json');
    if (appJsonPath) appJson = JSON.parse(fs.readFileSync(appJsonPath, 'utf8'));
  } catch { /* non-fatal */ }

  // 3. Load BCQuality knowledge files
  const knowledgeFiles = loadKnowledgeFiles([
    'microsoft/knowledge/performance',
    'community/knowledge/performance',
    'microsoft/knowledge/security',
    'community/knowledge/security',
  ]);
  console.log(`Loaded ${knowledgeFiles.length} BCQuality knowledge files`);

  // 4. Build prompts
  const systemPrompt = buildSystemPrompt(knowledgeFiles);
  const userPrompt   = buildUserPrompt(alFiles, appJson);

  // 5. Call GitHub Models
  console.log(`Calling GitHub Models (${MODEL})…`);
  let report;
  try {
    report = await callModels(systemPrompt, userPrompt);
  } catch (err) {
    console.error(`GitHub Models call failed: ${err.message}`);
    // Do not fail the workflow — the build should not block on AI review
    process.exit(0);
  }

  // 6. Post PR review
  await postReview(report, alFiles);
}

main().catch(err => {
  console.error(`BCQuality review error: ${err.message}`);
  process.exit(1);
});
