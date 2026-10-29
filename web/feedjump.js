/* ================= Jump to the latest comment (Mac app and phone) =================
   In the Mac app (html.mac-chrome) and on the phone, a task's comments (and a thread's replies) get a round "jump to the latest" button once you've scrolled
   up, or a "2 new comments" pill when comments arrive meanwhile (styles: styles.css .jl). At the latest, new comments
   stay in view. The website on a computer is unchanged. */
const FeedJump = (() => {
  const on = () => document.documentElement.classList.contains('mac-chrome') || (typeof Phone !== 'undefined' && Phone.on);
  const NEAR = 80;                       // within this many pixels of the end counts as "at the latest"
  const st = { taskId: null, thread: null, atEnd: true, seen: new Set() };
  const keyOf = () => `${ui.taskId}|${ui.thread || ''}|${ui.sideTab}|${ui.activityFilter}`;
  let lastKey = null;
  const atEnd = (feed) => feed.scrollHeight - feed.scrollTop - feed.clientHeight <= NEAR;
  const ids = (t) => new Set((t.comments || []).map((c) => c.id));
  function fresh(t) {
    return (t.comments || []).filter((c) => !st.seen.has(c.id) && c.authorId !== currentUserId && (!ui.thread || c.parentId === ui.thread || c.id === ui.thread));
  }
  function paint(feed, t) {
    const col = feed.parentElement;
    let b = col.querySelector(':scope > .jl');
    const show = !atEnd(feed);
    if (!show) { if (b) b.remove(); st.atEnd = true; st.seen = ids(t); return; }
    st.atEnd = false;
    const news = fresh(t);
    const html = news.length
      ? `<span class="jl-avs">${[...new Set(news.map((c) => c.authorId))].slice(0, 2).map((id) => avatarHTML(id, 22)).join('')}</span>${news.length} new comment${news.length === 1 ? '' : 's'}${icon('arrow-down')}`
      : icon('arrow-down');
    if (!b) {
      b = document.createElement('button');
      b.type = 'button';
      b.addEventListener('click', () => { feed.scrollTo({ top: feed.scrollHeight, behavior: 'smooth' }); });
      col.appendChild(b);
    }
    b.className = 'jl ' + (news.length ? 'jl-new' : 'jl-round');
    b.setAttribute('aria-label', news.length ? `${news.length} new comments — jump to the latest` : 'Jump to the latest comment');
    if (b.dataset.html !== html) { b.innerHTML = html; b.dataset.html = html; }
    place(col);
  }
  // always just above the comment box, also when it grows (files added, more lines, the attach bar)
  function place(col) {
    const b = col.querySelector(':scope > .jl'), comp = col.querySelector('.tm-composer');
    if (b) b.style.bottom = ((comp ? comp.offsetHeight : 0) + 14) + 'px';
    if (comp && typeof ResizeObserver !== 'undefined' && col.__jlComp !== comp) {
      if (col.__jlRO) col.__jlRO.disconnect();
      col.__jlComp = comp;
      col.__jlRO = new ResizeObserver(() => place(col));
      col.__jlRO.observe(comp);
    }
  }
  // after the task page is drawn (app.js renderDetail)
  function afterDetail(pane, t, prev) {
    if (!on() || !t) return;
    const feed = pane.querySelector('.tm-feed');
    if (!feed) return;
    const key = keyOf();
    if (key !== lastKey) { lastKey = key; st.atEnd = true; st.seen = ids(t); }
    else if (prev && st.atEnd) feed.scrollTop = feed.scrollHeight;       // at the latest: new comments stay in view
    if (atEnd(feed)) st.seen = ids(t);
    paint(feed, t);
    feed.addEventListener('scroll', () => { const tt = task(ui.taskId); if (tt) paint(feed, tt); }, { passive: true });
  }
  return { on, afterDetail };
})();
