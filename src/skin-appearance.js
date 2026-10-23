// Synchronize only appearance, using feature-detected native setters when present.
// Called inside the application's verified renderer by the skin bootstrap.
async function skinStudioSyncAppearance(app, mode) {
  if (!['light', 'dark'].includes(mode)) return { applied: false, reason: 'unspecified' };
  const root = document.documentElement;
  const workBuddyRenderer = () => document.body?.dataset.applicationName === 'workbuddy' ||
    (new URL(location.href).searchParams.get('windowKind') === 'settings' &&
     !!window.workbuddyDesktop && !!document.querySelector('.settings-window-root'));
  const bounded = promise => Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(Error('Appearance update timed out')), 4000))
  ]);
  const candidates = [];
  for (const host of [document.getElementById('root'), document.getElementById('app')]) {
    if (!host) continue;
    for (const key of Object.keys(host)) {
      if (key.startsWith('__reactContainer$')) candidates.push(host[key]);
    }
  }
  function nativeThemeState() {
    const seen = new Set(), stack = [...candidates];
    while (stack.length && seen.size < 30000) {
      const fiber = stack.pop();
      if (!fiber || seen.has(fiber)) continue;
      seen.add(fiber);
      try {
        const value = fiber.memoizedProps?.value;
        const state = typeof value?.getState === 'function' ? value.getState() : value;
        if (typeof state?.setTheme === 'function' && typeof state.theme === 'string') return state;
      } catch {}
      stack.push(fiber.child, fiber.sibling);
    }
    return null;
  }
  function monkeyThemeName() {
    const names = new Set();
    let visited = 0;
    const visit = rules => {
      for (const rule of rules) {
        if (++visited > 20000) return;
        for (const match of (rule.selectorText || '').matchAll(/\[data-theme\s*=\s*["']?([\w-]+)["']?\]/g)) names.add(match[1]);
        if (rule.cssRules) visit(rule.cssRules);
      }
    };
    for (const sheet of document.styleSheets) { try { visit(sheet.cssRules); } catch {} }
    const current = root.getAttribute('data-theme') || '';
    const preferred = current.startsWith('mc-') ? [`mc-${mode}`, mode] : [mode, `mc-${mode}`];
    return preferred.find(name => names.has(name)) || mode;
  }
  let method = 'runtime', persisted = false, themeName = mode, nativeError = null;
  try {
    if (app === 'zcode') {
      themeName = `zai-${mode}`;
      const state = nativeThemeState();
      if (state) {
        const nativeName = /^(light|dark|system|auto)$/.test(state.theme) ? mode : themeName;
        if (state.theme !== nativeName) await bounded(Promise.resolve(state.setTheme(nativeName)));
        method = 'native-store'; persisted = true;
      } else {
        const old = localStorage.getItem('zcode-theme');
        if (old !== themeName) {
          localStorage.setItem('zcode-theme', themeName);
          window.dispatchEvent(new StorageEvent('storage', { key: 'zcode-theme', oldValue: old, newValue: themeName, storageArea: localStorage }));
        }
        method = 'native-preference'; persisted = true;
      }
    } else if (app === 'codex') {
      const urls = [...document.querySelectorAll('script[src],link[rel="modulepreload"]')].map(e => e.src || e.href);
      const url = urls.find(value => /\/app-shared-[^/]+\.js(?:\?|$)/.test(value));
      if (url) {
        const module = await bounded(import(url));
        const find = test => {
          for (const value of Object.values(module)) { try { if (test(value)) return value; } catch {} }
        };
        const definitions = find(v => v && typeof v === 'object' && v.theme?.key === 'appearanceTheme');
        const host = find(v => v && typeof v === 'object' && typeof v.settings?.write === 'function');
        if (definitions && host) {
          const old = typeof host.settings.read === 'function' ? await bounded(host.settings.read(definitions.theme.key)) : null;
          if (old?.configured !== mode) await bounded(host.settings.write(definitions.theme.key, mode));
          method = 'native-settings'; persisted = true;
        } else if (definitions) {
          const write = find(v => typeof v === 'function' && v.length === 2 && /\.settings\.write\(/.test(Function.prototype.toString.call(v)));
          if (write) { await bounded(write(definitions.theme, mode)); method = 'native-settings'; persisted = true; }
        }
      }
    } else if (app === 'workbuddy') {
      if (!workBuddyRenderer()) throw Error('Not a WorkBuddy renderer');
      // Reuse the loaded native manager: its listeners update React and its
      // own serializer preserves WorkBuddy's theme preference schema.
      const base = new URL('./assets/', location.href);
      const urls = [...performance.getEntriesByType('resource').map(e => e.name),
        ...[...document.querySelectorAll('script[src],link[rel="modulepreload"]')].map(e => e.src || e.href)];
      const url = urls.find(value => {
        try {
          const u = new URL(value);
          return u.protocol === base.protocol && u.host === base.host &&
            u.pathname.startsWith(base.pathname) && /^theme-[\w-]+\.js$/.test(u.pathname.slice(base.pathname.length));
        } catch { return false; }
      });
      if (url) {
        const module = await bounded(import(url));
        const getManager = Object.values(module).find(v => typeof v === 'function' && v.name === 'getThemeManager');
        if (getManager) {
          const manager = getManager();
          if (typeof manager?.setTheme === 'function' && typeof manager?.getTheme === 'function') {
            await bounded(Promise.resolve(manager.setTheme(mode)));
            method = 'native-store'; persisted = true;
          }
        }
      }
    } else if (app === 'opencode') {
      // OpenCode's Theme provider listens to this native preference's storage
      // event, updating Solid state, theme CSS and the desktop host together.
      const key = 'opencode-color-scheme', old = localStorage.getItem(key);
      if (old !== mode || root.getAttribute('data-color-scheme') !== mode) {
        localStorage.setItem(key, mode);
        window.dispatchEvent(new StorageEvent('storage', { key, oldValue: old, newValue: mode, storageArea: localStorage }));
      }
      method = 'native-preference'; persisted = true;
    } else if (app === 'monkeycode') {
      themeName = monkeyThemeName();
      const state = nativeThemeState();
      if (state) {
        const nativeName = /^(light|dark|system|auto)$/.test(state.theme) ? mode : themeName;
        if (state.theme !== nativeName) await bounded(Promise.resolve(state.setTheme(nativeName)));
        method = 'native-store'; persisted = true;
      } else {
        // Preserve the existing preference's encoding; unknown formats stay untouched.
        const old = localStorage.getItem('mc.theme');
        if (old !== null) {
          let parsed; try { parsed = JSON.parse(old); } catch { parsed = old; }
          if (typeof parsed === 'string') {
            const next = old.startsWith('"') ? JSON.stringify(themeName) : themeName;
            if (old !== next) {
              localStorage.setItem('mc.theme', next);
              window.dispatchEvent(new StorageEvent('storage', { key: 'mc.theme', oldValue: old, newValue: next, storageArea: localStorage }));
            }
            method = 'native-preference'; persisted = true;
          }
        }
      }
    }
  } catch (error) { nativeError = String(error?.message || error); }
  // Apply immediately as well, covering startup frames and apps without a native API.
  if (app === 'zcode') {
    root.classList.toggle('theme-zai-light', mode === 'light');
    root.classList.toggle('theme-zai-dark', mode === 'dark');
    root.classList.toggle('dark', mode === 'dark');
  } else if (app === 'workbuddy') {
    if (!workBuddyRenderer()) throw Error('Not a WorkBuddy renderer');
    for (const element of [root, document.body]) {
      for (const prefix of ['', 'cb-', 'vscode-']) {
        element.classList.toggle(prefix + 'light', mode === 'light');
        element.classList.toggle(prefix + 'dark', mode === 'dark');
      }
    }
    root.setAttribute('data-theme', mode);
    document.body.setAttribute('data-vscode-theme-kind', `vscode-${mode}`);
    document.body.setAttribute('data-vscode-theme-name', mode === 'light' ? 'IDE Light' : 'IDE Night');
  } else if (app === 'opencode') {
    // data-theme is the native palette ID (e.g. oc-2), not the color scheme.
    root.setAttribute('data-color-scheme', mode);
  } else {
    root.setAttribute('data-theme', themeName);
    if (app === 'monkeycode') root.classList.toggle('dark', mode === 'dark');
  }
  root.style.colorScheme = mode;
  root.setAttribute('data-skin-appearance', mode);
  const result = { app, mode, method, persisted, applied: true, nativeError };
  window.__SKIN_STUDIO_APPEARANCE = result;
  return result;
}
