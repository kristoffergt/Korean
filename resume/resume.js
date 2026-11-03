// Shared by /resume, /kr/resume and /vn/resume. Each page marks where a
// resume goes with data-resume-id="<resume_content id>" (and, for a download
// link filled from that row's pdf_url, data-resume-pdf="<same id>"), then
// calls loadResumes(). The pages load this as resume.js?v=N: the site's
// service worker serves an asset it has seen from its cache by URL, so bump
// N in all three pages whenever this file changes.
//
// The content comes from the resume_content table (see sql
// migrations/resume_content_sync_migration.sql and resume_versions_migration.sql)
// instead of hardcoded HTML, so re-syncing a page from an updated resume
// doesn't require hand-editing these files -- see the "Sync resume from PDF"
// section in account settings, which writes to that same table.
(function(){
const SUPABASE_URL = 'https://kbqwitmxpmkueryjsyip.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImticXdpdG14cG1rdWVyeWpzeWlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1NzIxNjUsImV4cCI6MjEwMTE0ODE2NX0.hOuxXxjfPemuSpthbMAD7tz30oxBkI3CyyZ8fwgwZTc';
// Only the site's own resume bucket is linked as a download.
const PDF_PREFIX = SUPABASE_URL + '/storage/v1/object/public/resume/';
const FAILED = {
  en: 'Could not load resume content.',
  ko: '이력서를 불러올 수 없습니다.',
  vi: 'Không thể tải sơ yếu lý lịch.'
};

function escapeHtml(s){
  return String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function filled(v){ return v != null && String(v).trim() !== ''; }
// entry.role (e.g. "Store Operations") is optional and always rendered in
// italics after an en dash, matching entries like "365 Discount – Store
// Operations" -- kept as a separate plain-text field rather than expecting
// title to carry hand-authored <em> markup, since title comes from an
// AI-driven paste-in and every other field is plain text + escaped.
function renderEntry(entry){
  const bullets = entry.bullets || [];
  const hasSubtitle = filled(entry.subtitle);
  const hasRole = filled(entry.role);
  const titleHtml = escapeHtml(entry.title) + (hasRole ? ` – <em>${escapeHtml(entry.role)}</em>` : '');
  const rowHtml = `<div class="r-row"><span class="r-left">${titleHtml}</span><span class="r-right">${escapeHtml(entry.location)}</span></div>`;
  let subHtml = '';
  let bulletsHtml = '';
  if(hasSubtitle){
    subHtml = `<div class="r-sub"><span>${escapeHtml(entry.subtitle)}</span><span class="r-right">${escapeHtml(entry.date)}</span></div>`;
    bulletsHtml = bullets.length ? `<ul>${bullets.map(b=>`<li>${escapeHtml(b)}</li>`).join('')}</ul>` : '';
  } else if(bullets.length){
    const [first, ...rest] = bullets;
    // Two renderings of the same date: r-date-float (desktop, floated into
    // the first bullet so it shares that line instead of an empty row of
    // its own) and r-date-mobile (a plain line matching how r-sub shows a
    // date when there IS a subtitle) -- CSS shows exactly one of the two
    // per breakpoint. Keeping the date inside the bulleted <li> on mobile
    // too broke the bullet marker's position (see the r-date-float mobile
    // rule in resume.css), so mobile gets its own non-bulleted line instead.
    subHtml = `<div class="r-date-mobile">${escapeHtml(entry.date)}</div>`;
    bulletsHtml = `<ul><li><span class="r-date-float">${escapeHtml(entry.date)}</span>${escapeHtml(first)}</li>${rest.map(b=>`<li>${escapeHtml(b)}</li>`).join('')}</ul>`;
  } else if(entry.date){
    // No subtitle and no bullets to float the date into -- fall back to a
    // plain right-aligned line rather than silently dropping the date.
    bulletsHtml = `<div style="text-align:right;font-style:italic;">${escapeHtml(entry.date)}</div>`;
  }
  return `<div class="r-entry">${rowHtml}${subHtml}${bulletsHtml}</div>`;
}
function renderInfoSection(section){
  return (section.info || []).map(i=>
    `<div class="r-info-row"><span class="r-info-label">${escapeHtml(i.label)}:</span><span>${escapeHtml(i.value)}</span></div>`
  ).join('');
}
// Links are stored without a scheme (the sync prompt asks for "no https://",
// to match how they read on a printed page), so the href needs one added
// back -- tel:/mailto: don't have that problem, they're not what's displayed.
function webLink(v){
  return `<a href="https://${escapeHtml(String(v).replace(/^https?:\/\//i, ''))}" target="_blank" rel="noopener">${escapeHtml(v)}</a>`;
}
function renderHeader(h){
  h = h || {};
  const links = [h.website, h.linkedin].filter(filled).map(webLink).join(' &nbsp;|&nbsp; ');
  const telHref = h.phone ? `tel:${h.phone.replace(/[^\d+]/g, '')}` : '';
  return `<div class="r-header">
      <div>
        <p class="r-name">${escapeHtml(h.name)}</p>
        ${filled(h.name_alt) ? `<p class="r-name-alt">${escapeHtml(h.name_alt)}</p>` : ''}
        <div class="r-linkedin">${links}</div>
        ${filled(h.details) ? `<div class="r-details">${escapeHtml(h.details)}</div>` : ''}
      </div>
      <div class="r-contact">
        <div>${escapeHtml(h.location)}</div>
        <div>${h.phone ? `<a href="${escapeHtml(telHref)}">${escapeHtml(h.phone)}</a>` : ''}</div>
        <div>${h.email ? `<a href="mailto:${escapeHtml(h.email)}">${escapeHtml(h.email)}</a>` : ''}</div>
      </div>
    </div>`;
}
// A section is a paragraph (text), label/value rows (info), or entries.
function renderSection(sec){
  const head = `<h2 class="r-section">${escapeHtml(sec.title)}</h2>`;
  if(filled(sec.text)) return head + `<p class="r-text">${escapeHtml(sec.text)}</p>`;
  if(sec.info) return head + renderInfoSection(sec);
  return head + (sec.entries || []).map(renderEntry).join('');
}
function renderResume(data, root){
  const body = (data.sections || []).map(renderSection).join('');
  root.innerHTML = renderHeader(data.header) + `<div class="r-body">${body}</div>`;
}
function langOf(root){
  return ((root.closest('[lang]') || document.documentElement).lang || 'en').slice(0, 2);
}
function fail(root){
  root.innerHTML = `<p class="hint">${FAILED[langOf(root)] || FAILED.en}</p>`;
  root.removeAttribute('aria-busy');
}
// A skeleton of the card while its row is on the way (Kristoffer, 3 Nov: "i
// wish we had a skeleton load (you know where you sorta see the preview of
// what it is opening, like the shapes of it)"): the navy band with a name and
// the contact lines, then three sections. Fixed widths, not random, so it
// looks the same every time. The shapes are hidden from screen readers; the
// word is what they read. resume.css holds the 150 ms delay before it shows.
const LOADING = { en: 'Loading', ko: '불러오는 중', vi: 'Đang tải' };
function skeletonHtml(root){
  const bar = (w, cls)=> `<span class="r-skel-bar${cls ? ' ' + cls : ''}" style="width:${w};"></span>`;
  const section = (head, lines)=> bar(head, 'r-skel-head') + bar('100%', 'r-skel-rule') + lines.map(w=> bar(w)).join('');
  return `<div class="r-skel"><span class="r-skel-sr">${LOADING[langOf(root)] || LOADING.en}</span>
    <div aria-hidden="true">
      <div class="r-header"><div class="r-skel-who">${bar('42%', 'r-skel-name')}${bar('30%')}</div>
        <div class="r-skel-contact">${bar('120px')}${bar('100px')}${bar('150px')}</div></div>
      <div class="r-body">${section('22%', ['96%', '88%', '60%'])}${section('28%', ['70%', '92%', '84%', '76%', '48%'])}${section('18%', ['64%', '58%'])}</div>
    </div></div>`;
}
window.loadResumes = function(){
  const roots = Array.from(document.querySelectorAll('[data-resume-id]'));
  const ids = roots.map(r=> r.dataset.resumeId);
  roots.forEach(root=>{ root.innerHTML = skeletonHtml(root); root.setAttribute('aria-busy', 'true'); });
  fetch(`${SUPABASE_URL}/rest/v1/resume_content?id=in.(${ids.map(encodeURIComponent).join(',')})&select=id,content,pdf_url`, {
    headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}` }
  })
    .then(r=> r.ok ? r.json() : Promise.reject(r.status))
    .then(rows=>{
      roots.forEach(root=>{
        const id = root.dataset.resumeId;
        const row = (rows || []).find(x=> x.id === id);
        if(!row || !row.content){ fail(root); return; }
        renderResume(row.content, root);
        root.removeAttribute('aria-busy');
        // A version without its own PDF shows no download at all.
        const pdf = document.querySelector(`[data-resume-pdf="${id}"]`);
        if(pdf && typeof row.pdf_url === 'string' && row.pdf_url.startsWith(PDF_PREFIX)){
          pdf.href = row.pdf_url;
          pdf.hidden = false;
        }
      });
    })
    .catch(()=> roots.forEach(fail));
};
})();
