// The plain wiki renderer's page script: mobile drawer, sidebar collapse (+ Cmd/Ctrl+B), search,
// and sidebar accordions. Each page sets window.WIKI first:
//   root  "../" per folder level, so links written from the wiki root work in any folder
(function () {
  const { root: ROOT } = window.WIKI;
  const html = document.documentElement;
  const toggle = document.querySelector('.nav-toggle');
  const sidebar = document.getElementById('sidebar');
  const overlay = document.getElementById('overlay');

  // Mobile: the sidebar is a drawer behind the Menu button.
  function closeSidebar() { sidebar.classList.remove('open'); overlay.classList.remove('open'); }
  function toggleDrawer() { sidebar.classList.toggle('open'); overlay.classList.toggle('open'); }
  toggle.addEventListener('click', toggleDrawer);
  overlay.addEventListener('click', closeSidebar);

  // Desktop: collapse/expand the sidebar, remembered per browser. The <head> script applies a saved
  // "collapsed" before first paint, so there is no flash of the sidebar on load.
  const collapseBtn = document.getElementById('sidebar-collapse');
  function syncCollapse() {
    const collapsed = html.classList.contains('sidebar-collapsed');
    const label = collapsed ? 'Expand sidebar (Ctrl+B)' : 'Collapse sidebar (Ctrl+B)';
    collapseBtn.setAttribute('aria-expanded', String(!collapsed));
    collapseBtn.setAttribute('aria-label', label);
    collapseBtn.title = label;
  }
  function toggleCollapse() {
    const collapsed = html.classList.toggle('sidebar-collapsed');
    try { localStorage.setItem('wiki-sidebar', collapsed ? 'collapsed' : 'expanded'); } catch (e) {}
    syncCollapse();
  }
  collapseBtn.addEventListener('click', toggleCollapse);
  syncCollapse();

  // Cmd+B (Mac) / Ctrl+B: the same shortcut as the house apps. On a phone-width screen it opens and
  // closes the drawer instead, since there is no collapsed sidebar there.
  document.addEventListener('keydown', e => {
    if (e.key.toLowerCase() !== 'b' || !(e.metaKey || e.ctrlKey) || e.shiftKey || e.altKey) return;
    e.preventDefault();
    if (window.matchMedia('(max-width: 768px)').matches) toggleDrawer();
    else toggleCollapse();
  });

  // Search. The index lives in search.json, fetched once, the first time someone uses the search box,
  // so pages stay small.
  const searchInput = document.getElementById('search');
  const searchResults = document.getElementById('search-results');
  let searchIndex = null;
  let loading = null;
  let focusIdx = -1;

  function loadIndex() {
    loading = loading || fetch(ROOT + 'search.json', { credentials: 'same-origin' })
      .then(r => (r.ok ? r.json() : []))
      .catch(() => [])
      .then(list => { searchIndex = list; });
    return loading;
  }

  function escapeHtml(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

  function getSnippet(text, query) {
    const i = text.indexOf(query);
    if (i === -1) return '';
    const start = Math.max(0, i - 40);
    const end = Math.min(text.length, i + query.length + 60);
    const snippet = (start > 0 ? '...' : '') + text.slice(start, end) + (end < text.length ? '...' : '');
    const safe = query.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&');
    return escapeHtml(snippet).replace(new RegExp('(' + safe + ')', 'gi'), '<mark>$1</mark>');
  }

  async function doSearch() {
    const q = searchInput.value.trim().toLowerCase();
    if (q.length < 2) { searchResults.classList.remove('open'); return; }
    if (!searchIndex) await loadIndex();
    if (searchInput.value.trim().toLowerCase() !== q) return; // typing moved on while the index loaded
    const hits = searchIndex
      .filter(p => p.title.toLowerCase().includes(q) || p.text.includes(q))
      .slice(0, 8);
    searchResults.innerHTML = hits.length
      ? hits.map(h =>
          '<a class="search-result" href="' + ROOT + h.href + '">' +
            '<div class="search-result-title">' + escapeHtml(h.title) + '</div>' +
            '<div class="search-result-snippet">' + getSnippet(h.text, q) + '</div>' +
          '</a>').join('')
      : '<div class="search-empty">No results</div>';
    focusIdx = -1;
    searchResults.classList.add('open');
  }

  searchInput.addEventListener('input', doSearch);
  searchInput.addEventListener('focus', () => { loadIndex(); if (searchInput.value.trim().length >= 2) doSearch(); });
  document.addEventListener('click', e => {
    if (!e.target.closest('.search-wrap')) searchResults.classList.remove('open');
  });
  searchInput.addEventListener('keydown', e => {
    const items = searchResults.querySelectorAll('.search-result');
    if (!items.length) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); focusIdx = Math.min(focusIdx + 1, items.length - 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); focusIdx = Math.max(focusIdx - 1, 0); }
    else if (e.key === 'Enter' && focusIdx >= 0) { e.preventDefault(); items[focusIdx].click(); return; }
    else if (e.key === 'Escape') { searchResults.classList.remove('open'); return; }
    else return;
    items.forEach((el, i) => el.classList.toggle('focused', i === focusIdx));
  });

  // Project groups accordion.
  sidebar.addEventListener('click', e => {
    const btn = e.target.closest('.nav-project-toggle');
    if (!btn) return;
    const expanded = btn.getAttribute('aria-expanded') === 'true';
    btn.setAttribute('aria-expanded', String(!expanded));
    btn.nextElementSibling.hidden = expanded;
  });

  // Heading contents accordion.
  document.querySelectorAll('.toc-chevron').forEach(btn => {
    btn.addEventListener('click', e => {
      e.preventDefault();
      const expanded = btn.getAttribute('aria-expanded') === 'true';
      btn.setAttribute('aria-expanded', String(!expanded));
      const children = btn.closest('.toc-section').querySelector('.toc-children');
      if (children) children.hidden = expanded;
    });
  });
})();
