(()=>{
 const visible=e=>!!e&&!!e.getClientRects().length&&getComputedStyle(e).visibility!=='hidden';
 const nodes=s=>[...document.querySelectorAll(s)].filter(visible);
 const mode=(()=>{const r=document.documentElement;const a=[r.dataset.theme,r.dataset.colorScheme,r.getAttribute('class'),r.style.colorScheme,document.body?.dataset.vscodeThemeKind].join(' ');if(/(?:dark|night)/i.test(a))return 'dark';if(/(?:light|monkeycode|day)/i.test(a))return 'light';return 'unknown'})();
 const inputs=nodes('textarea,[contenteditable="true"],[role="textbox"]');
 const codes=nodes('pre');
 const menus=nodes('[role="menu"],[role="listbox"],[data-slot*="menu-content"],.dropdown-content,.menu:not(aside .menu)').filter(e=>e.matches('[role="listbox"],.dropdown-content,[role="menu"]')||!e.closest('[role="dialog"],dialog[open]'));
 const dialogs=nodes('[role="dialog"],dialog[open],[data-window-kind="settings"],[data-testid*="settings"],.settings-window-root').filter(e=>e.clientWidth>200&&e.clientHeight>120);
 const context=nodes('[data-slot="session-context-panel"],[data-component*="context"],[data-testid*="context-panel"],[aria-label*="上下文"],[aria-label*="Context"],[data-panel="context"]').filter(e=>e.clientWidth>150&&e.clientHeight>100);
 const panels=nodes('[data-slot="session-chat-panel"],[data-panel-id],[data-workbench-cell],[role="region"][aria-label*="格"],.mc-workbench-surface-100,.conversation-shell__main,.conversation-history-navigation,main > aside').filter(e=>e.clientWidth>120&&e.clientHeight>100);
 const scrollers=[...document.querySelectorAll('*')].filter(e=>visible(e)&&e.clientHeight>150&&e.scrollHeight>e.clientHeight*1.5&&/(auto|scroll)/.test(getComputedStyle(e).overflowY));
 const chatScrollers=scrollers.filter(e=>e.closest('main,.thread-scroll-container,[data-slot="session-chat-panel"],.conversation-shell__main')&&!e.closest('aside,[role="dialog"],[role="menu"],[role="listbox"]'));
 const clip=codes.filter(e=>e.scrollWidth>e.clientWidth+2&&!/(auto|scroll)/.test(getComputedStyle(e).overflowX)).length;
 const tiny=nodes('button,[role="button"]').filter(e=>{const s=getComputedStyle(e);return !e.disabled&&s.opacity==='0'}).length;
 const scenes={
  'long-chat':{present:chatScrollers.length>0,count:chatScrollers.length},
  code:{present:codes.length>0,count:codes.length,clipped:clip},
  composer:{present:inputs.length>0,count:inputs.length},
  split:{present:panels.length>=2,count:panels.length},
  context:{present:context.length>0,count:context.length},
  menu:{present:menus.length>0,count:menus.length},
  settings:{present:dialogs.length>0||/\/(?:settings|preferences)(?:[/?#]|$)|[?&](?:windowKind|view|page)=(?:settings|preferences)(?:[&#]|$)/i.test(decodeURIComponent(location.href)),count:dialogs.length}
 };
 const surfaces=[...inputs,...codes,...menus,...dialogs,...context].slice(0,40).map(e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return {tag:e.tagName,color:s.color,background:s.backgroundColor,opacity:s.opacity,width:Math.round(r.width),height:Math.round(r.height),overflowX:s.overflowX}});
 const style=document.getElementById('skin-studio-style')||document.getElementById('zc-skin-style');
 return {mode,scenes,surfaces,invisibleEnabledButtons:tiny,viewport:{width:innerWidth,height:innerHeight},marker:window.__SKIN_STUDIO||window.__ZC_SKIN||'',styleActive:!!(style?.sheet&&!style.sheet.disabled&&style.textContent.trim()),note:'Automatic observations only; missing scenes are untested. Visual review is required.'};
})()
