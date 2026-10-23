// Native OpenCode component/token fixture; compositing over both wallpaper extremes.
(() => {
  const root = document.documentElement;
  root.dataset.theme = 'oc-2';
  const host = document.createElement('div');
  host.id = 'oc-fixture';
  // Match Tailwind's alias declared on :root. Rebinding only the source token
  // on a pane does not change this already computed, inherited alias.
  const nativeCss = document.createElement('style');
  nativeCss.textContent = ':root{--color-v2-background-bg-base:var(--v2-background-bg-base)}.bg-v2-background-bg-base{background-color:var(--color-v2-background-bg-base)}[data-component="tabs"]{background:var(--v2-background-bg-base)}';
  document.head.appendChild(nativeCss);
  host.innerHTML = `<header data-slot="titlebar-v2" style="position:relative;width:100px;max-width:100px;height:44px">Title</header>
    <aside>Sidebar</aside><section style="background:var(--v2-background-bg-base,white);color:var(--v2-text-text-base,black)">
    <button id="oc-ghost" data-component="icon-button-v2" style="background:transparent;color:var(--v2-icon-icon-base)"><svg></svg>Tool</button>
    <div data-component="session-composer-dock"><form data-component="composer"><button id="oc-disabled" disabled style="opacity:.4">Disabled</button>
    <button id="oc-send" style="background:rgb(20,127,153);color:white">Send</button><span id="oc-syntax" style="color:rgb(224,49,49)">Code</span></form></div>
    <div data-component="menu-v2-content" role="menu">Menu<div style="background:var(--v2-background-bg-base)">Nested</div></div></section>
    <div data-slot="session-chat-panel"><div id="oc-session" class="bg-v2-background-bg-base">
      <div data-session-title><div class="bg-v2-background-bg-base">Sticky title</div></div>
      <div data-slot="session-timeline-scroll">Conversation</div>
    </div></div>
    <div data-slot="session-side-panel-content"><aside id="oc-side" class="bg-v2-background-bg-base">
      <div data-slot="session-review-content"><div class="bg-v2-background-bg-base"><div class="bg-v2-background-bg-base">
        <div data-component="tabs"><div id="oc-context" class="bg-v2-background-bg-base">Context<aside class="bg-v2-background-bg-base">File tree</aside></div></div>
      </div></div></div>
      <div data-component="menu-v2-content" role="menu"><div class="bg-v2-background-bg-base">Nested menu</div></div>
      <div id="oc-raised" style="background:var(--v2-background-bg-layer-01)">Raised card</div>
      <div id="oc-diff" style="background:rgb(1,41,2);color:rgb(107,213,134)">Diff</div>
    </aside></div>`;
  document.getElementById('root').appendChild(host);
  const panel = host.querySelector('section'), aside = host.querySelector('aside'), menu = host.querySelector('[role=menu]');
  const ctx = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
  const pixel = (css, under) => {
    ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = under; ctx.fillRect(0, 0, 1, 1);
    ctx.fillStyle = css; ctx.fillRect(0, 0, 1, 1);
    return [...ctx.getImageData(0, 0, 1, 1).data].slice(0, 3);
  };
  const lum = rgb => rgb.map(x => { x /= 255; return x <= .04045 ? x / 12.92 : ((x + .055) / 1.055) ** 2.4; }).reduce((s, x, i) => s + x * [.2126, .7152, .0722][i], 0);
  const contrast = [], modes = [];
  for (const mode of ['light', 'dark']) {
    root.dataset.colorScheme = mode;
    const session = document.getElementById('oc-session'), side = document.getElementById('oc-side');
    for (const el of [panel, aside, session, side]) {
      const s = getComputedStyle(el), text = lum(pixel(s.color, '#000'));
      for (const wallpaper of ['#000', '#fff']) {
        const bg = lum(pixel(s.backgroundColor, wallpaper));
        contrast.push((Math.max(text, bg) + .05) / (Math.min(text, bg) + .05));
      }
    }
    const expected = mode === 'dark' ? 'rgb(23, 30, 41)' : 'rgb(248, 250, 252)';
    const header = host.querySelector('header');
    modes.push(getComputedStyle(menu).backgroundColor === expected && getComputedStyle(menu.firstElementChild).backgroundColor === expected &&
      getComputedStyle(host.querySelector('form')).backdropFilter === 'blur(10px)' &&
      getComputedStyle(header, '::before').width === `${innerWidth}px` && header.getBoundingClientRect().width === 100 &&
      getComputedStyle(document.getElementById('oc-ghost')).backgroundColor === 'rgba(0, 0, 0, 0)');
    const transparent = e => getComputedStyle(e).backgroundColor === 'rgba(0, 0, 0, 0)';
    const wrappers = side.querySelectorAll('[data-slot="session-review-content"] *');
    const overlay = side.querySelector('[role="menu"]');
    modes.push(getComputedStyle(session).backgroundColor === getComputedStyle(side).backgroundColor &&
      [...wrappers].every(transparent) && getComputedStyle(session).backdropFilter === 'none' && getComputedStyle(side).backdropFilter === 'none' &&
      getComputedStyle(session.querySelector('[data-session-title] > div')).backgroundColor === expected &&
      getComputedStyle(overlay).backgroundColor === expected && getComputedStyle(overlay.firstElementChild).backgroundColor === expected &&
      !transparent(document.getElementById('oc-raised')) && getComputedStyle(document.getElementById('oc-diff')).backgroundColor === 'rgb(1, 41, 2)');
  }
  const states = getComputedStyle(document.getElementById('oc-disabled')).opacity === '0.4' &&
    getComputedStyle(document.getElementById('oc-send')).backgroundColor === 'rgb(20, 127, 153)' &&
    getComputedStyle(document.getElementById('oc-syntax')).color === 'rgb(224, 49, 49)';
  return { pass: modes.every(Boolean) && states && Math.min(...contrast) >= 4.5, modes, states, minContrast: Math.min(...contrast) };
})()
