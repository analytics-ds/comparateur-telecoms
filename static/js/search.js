/* Recherche client-side : index JSON genere par Hugo (/index.json et /en/index.json).
   Zero dependance, chargement de l'index a la premiere ouverture seulement. */
(function () {
  var root = document.getElementById('search');
  if (!root) return;

  var input   = root.querySelector('.search-input');
  var list    = root.querySelector('.search-results');
  var status  = root.querySelector('.search-status');
  var toggles = document.querySelectorAll('.search-toggle');
  var closers = root.querySelectorAll('[data-search-close]');

  var TXT = {
    empty: root.dataset.i18nEmpty || 'Aucun resultat',
    one:   root.dataset.i18nOne   || '1 resultat',
    many:  root.dataset.i18nMany  || '%d resultats',
    error: root.dataset.i18nError || 'Recherche indisponible'
  };

  var items = null, loading = false, timer = null, active = -1, lastFocus = null;

  /* ---------- utilitaires ---------- */
  function fold(s) {
    return (s || '').toString().toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[\u2019']/g, ' ');
  }
  function esc(s) {
    return (s || '').replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function highlight(text, tokens) {
    var out = esc(text), folded = fold(text);
    if (!tokens.length) return out;
    // positions a marquer, calculees sur la version pliee (meme longueur que l'original)
    var marks = [];
    tokens.forEach(function (tk) {
      var from = 0, at;
      while ((at = folded.indexOf(tk, from)) !== -1) {
        marks.push([at, at + tk.length]);
        from = at + tk.length;
      }
    });
    if (!marks.length) return out;
    marks.sort(function (a, b) { return a[0] - b[0]; });
    var merged = [marks[0]];
    for (var i = 1; i < marks.length; i++) {
      var last = merged[merged.length - 1];
      if (marks[i][0] <= last[1]) last[1] = Math.max(last[1], marks[i][1]);
      else merged.push(marks[i]);
    }
    var res = '', cursor = 0;
    merged.forEach(function (m) {
      res += esc(text.slice(cursor, m[0])) + '<mark>' + esc(text.slice(m[0], m[1])) + '</mark>';
      cursor = m[1];
    });
    return res + esc(text.slice(cursor));
  }
  function snippet(text, tokens) {
    if (!text) return '';
    var folded = fold(text), at = -1;
    for (var i = 0; i < tokens.length && at === -1; i++) at = folded.indexOf(tokens[i]);
    if (at === -1) return text.slice(0, 150);
    var start = Math.max(0, at - 60);
    var cut = text.slice(start, start + 190);
    return (start > 0 ? '... ' : '') + cut;
  }

  /* ---------- index ---------- */
  function load() {
    if (items || loading) return Promise.resolve();
    loading = true;
    var url = root.dataset.index || '/index.json';
    return fetch(url, { credentials: 'same-origin' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (data) {
        items = (data.items || []).map(function (it) {
          it._t = fold(it.t);
          it._d = fold(it.d);
          it._k = fold([].concat(it.c || [], it.g || [], it.a || '').join(' '));
          it._x = fold(it.x);
          return it;
        });
        loading = false;
      })
      .catch(function () {
        loading = false;
        status.textContent = TXT.error;
      });
  }

  /* ---------- scoring ---------- */
  function search(q) {
    var folded = fold(q).trim();
    var tokens = folded.split(/\s+/).filter(function (t) { return t.length > 1; });
    if (!tokens.length || !items) return { tokens: tokens, hits: [] };

    var hits = [];
    items.forEach(function (it) {
      var score = 0, all = true;
      tokens.forEach(function (tk) {
        var here = 0;
        if (it._t.indexOf(tk) !== -1) here += it._t.indexOf(tk) === 0 ? 70 : 50;
        if (it._k.indexOf(tk) !== -1) here += 30;
        if (it._d.indexOf(tk) !== -1) here += 18;
        if (it._x.indexOf(tk) !== -1) here += 6;
        if (!here) all = false;
        score += here;
      });
      if (!all) return;                                  // tous les mots doivent apparaitre
      if (it._t.indexOf(folded) !== -1) score += 120;     // expression exacte dans le titre
      hits.push({ it: it, score: score });
    });
    hits.sort(function (a, b) { return b.score - a.score; });
    return { tokens: tokens, hits: hits.slice(0, 12) };
  }

  function render(q) {
    var r = search(q);
    list.innerHTML = '';
    active = -1;

    if (!r.tokens.length) { status.textContent = ''; return; }
    if (!r.hits.length) { status.textContent = TXT.empty; return; }

    status.textContent = r.hits.length === 1
      ? TXT.one
      : TXT.many.replace('%d', r.hits.length);

    r.hits.forEach(function (h, idx) {
      var it = h.it;
      var li = document.createElement('li');
      li.className = 'search-item';
      li.setAttribute('role', 'option');
      li.id = 'search-opt-' + idx;
      li.innerHTML =
        '<a href="' + esc(it.u) + '">' +
          (it.i ? '<span class="search-thumb"><img src="' + esc(it.i) + '" alt="" loading="lazy"></span>' : '<span class="search-thumb is-empty"></span>') +
          '<span class="search-text">' +
            '<span class="search-title">' + highlight(it.t, r.tokens) + '</span>' +
            '<span class="search-excerpt">' + highlight(snippet(it.d || it.x, r.tokens), r.tokens) + '</span>' +
            '<span class="search-meta">' +
              ((it.c && it.c.length) ? '<span class="search-cat">' + esc(it.c[0]) + '</span>' : '') +
              (it.dt ? '<span>' + esc(it.dt) + '</span>' : '') +
            '</span>' +
          '</span>' +
        '</a>';
      list.appendChild(li);
    });
  }

  /* ---------- navigation clavier ---------- */
  function setActive(next) {
    var opts = list.querySelectorAll('.search-item');
    if (!opts.length) return;
    if (active > -1) opts[active].classList.remove('is-active');
    active = (next + opts.length) % opts.length;
    opts[active].classList.add('is-active');
    input.setAttribute('aria-activedescendant', opts[active].id);
    opts[active].scrollIntoView({ block: 'nearest' });
  }

  /* ---------- ouverture / fermeture ---------- */
  function open(prefill) {
    if (!root.hidden) { input.focus(); return; }
    lastFocus = document.activeElement;
    root.hidden = false;
    document.body.classList.add('search-open');
    if (prefill) input.value = prefill;
    input.focus();
    input.select();
    load().then(function () { if (input.value) render(input.value); });
  }
  function close() {
    if (root.hidden) return;
    root.hidden = true;
    document.body.classList.remove('search-open');
    list.innerHTML = '';
    status.textContent = '';
    active = -1;
    input.removeAttribute('aria-activedescendant');
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  Array.prototype.forEach.call(toggles, function (b) {
    b.addEventListener('click', function (e) { e.preventDefault(); open(); });
  });
  Array.prototype.forEach.call(closers, function (b) {
    b.addEventListener('click', close);
  });

  input.addEventListener('input', function () {
    var q = input.value;
    clearTimeout(timer);
    timer = setTimeout(function () {
      load().then(function () { render(q); });
    }, 110);
  });

  input.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowDown') { e.preventDefault(); setActive(active + 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setActive(active - 1); }
    else if (e.key === 'Enter') {
      var opts = list.querySelectorAll('.search-item');
      var target = active > -1 ? opts[active] : opts[0];
      if (target) { e.preventDefault(); target.querySelector('a').click(); }
    }
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !root.hidden) { e.preventDefault(); close(); return; }
    if ((e.metaKey || e.ctrlKey) && (e.key === 'k' || e.key === 'K')) { e.preventDefault(); open(); return; }
    var tag = (e.target.tagName || '').toLowerCase();
    var typing = tag === 'input' || tag === 'textarea' || tag === 'select' || e.target.isContentEditable;
    if (e.key === '/' && !typing && root.hidden) { e.preventDefault(); open(); }
  });

  // Precharge l'index au survol du bouton, la premiere frappe est instantanee
  Array.prototype.forEach.call(toggles, function (b) {
    b.addEventListener('mouseenter', load, { once: true });
  });
})();
