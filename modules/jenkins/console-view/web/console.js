(() => {
  'use strict';
  const script = document.currentScript;
  const base = script?.dataset.backendJob || 'aof-back';
  const path = decodeURIComponent(location.pathname);
  const match = path.match(/\/job\/([^/]+)\/(?:\d+|lastBuild|lastCompletedBuild|lastSuccessfulBuild|lastFailedBuild)\/console(?:Full)?\/?$/);
  if (!match || ![base, base+'-dev', base+'-feature', base+'-release'].includes(match[1])) return;
  const start = () => {
    const consoleLog = document.querySelector('pre.console-output');
    if (!consoleLog) return;
    const style = document.createElement('style');
    // Jenkins adds absolute-positioned branch labels dynamically. Remove both
    // pseudo-elements entirely, including their layout, on every log fragment.
    style.textContent = `
      pre.aof-compact .pipeline-new-node,
      pre.aof-compact .pipeline-show-hide,
      pre.aof-compact .aof-routine { display: none !important; }
      pre.aof-compact [class*="pipeline-node-"]::before,
      pre.aof-compact [class*="pipeline-node-"]::after {
        display: none !important;
        content: none !important;
        position: static !important;
        transform: none !important;
      }
    `;
    document.head.append(style);
    consoleLog.classList.add('aof-compact');
    // An allowlist of routine notices: never hide a span containing an unknown line.
    const routine = line => /^(Sleeping for \d|Timeout set to expire in |Running in \/|Running on |Agent .* is provisioned from template |Created Pod: kubernetes |Still waiting to schedule task$|[‘'].+[’'] is offline$|using credential |Cloning the remote Git repository$|Using shallow clone with depth |Avoid fetching tags$|Honoring refspec on initial clone$|Cloning repository https:\/\/github.com\/akuzmin90\/aof-back.git$|Fetching upstream changes from https:\/\/github.com\/akuzmin90\/aof-back.git$|Checking out Revision |Commit message: |Archiving artifacts$)/.test(line);
    const refresh = () => {
      consoleLog.querySelectorAll('span[class*="pipeline-node-"]').forEach(span => {
        const lines = span.textContent.split('\n').filter(line => line.trim());
        span.classList.toggle('aof-routine', lines.length > 0 && lines.every(routine));
      });
    };
    refresh();
    // Also handle progressive console output while a build is running.
    new MutationObserver(refresh).observe(consoleLog, {childList:true, subtree:true, characterData:true});
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
