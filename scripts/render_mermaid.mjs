#!/usr/bin/env node
import fs from 'fs';
import path from 'path';

// Locate grok-mermaid from Pi installation or global node_modules
function findGrokMermaid() {
  const candidates = [
    '/home/hlu/.nvm/versions/node/v26.3.0/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/grok-mermaid/dist/index.js',
    path.join(process.env.HOME || '', '.nvm/versions/node/v26.3.0/lib/node_modules/@earendil-works/pi-coding-agent/node_modules/grok-mermaid/dist/index.js')
  ];

  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

async function main() {
  let input = '';
  if (process.argv[2]) {
    input = process.argv[2];
  } else {
    // Read from stdin
    input = fs.readFileSync(0, 'utf-8');
  }

  const trimmed = input.trim();
  if (!trimmed) {
    console.log(JSON.stringify({ success: false, error: 'Empty input' }));
    return;
  }

  const grokPath = findGrokMermaid();
  if (!grokPath) {
    console.log(JSON.stringify({ success: false, error: 'grok-mermaid engine not found' }));
    return;
  }

  try {
    const { render, diagramKind } = await import(grokPath);
    const art = render(trimmed);
    const kind = diagramKind(trimmed) || 'diagram';

    if (!art) {
      console.log(JSON.stringify({
        success: false,
        kind,
        error: 'Syntax error or unsupported diagram kind'
      }));
      return;
    }

    // Material 3 Expressive theme colors matching Astral Plasma
    const colors = {
      border: '#82aaff',
      edge: '#80cbc4',
      edgeLabel: '#ffcb6b',
      text: '#e2e2e9',
      title: '#c792ea',
      none: 'inherit'
    };

    const htmlLines = art.styled.map(row => {
      return row.map(span => {
        const col = colors[span.cls] || 'inherit';
        const escaped = span.text
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/ /g, '&nbsp;');
        if (col === 'inherit') return escaped;
        return `<span style="color:${col};">${escaped}</span>`;
      }).join('');
    });

    const html = `<pre style="font-family: monospace; font-size: 11px; line-height: 1.25; margin: 0;">${htmlLines.join('<br>')}</pre>`;

    console.log(JSON.stringify({
      success: true,
      kind,
      width: art.width || 40,
      lines: art.plain.length,
      plain: art.plain.join('\n'),
      html
    }));
  } catch (err) {
    console.log(JSON.stringify({
      success: false,
      error: String(err && err.message ? err.message : err)
    }));
  }
}

main();
