(() => {
    'use strict';
    const root = document.getElementById('interaction');
    const rows = document.getElementById('rows');
    const switchHint = document.getElementById('switch');
    let signature = '';
    let lastMessage = 0;
    function iconClasses(value) {
        // Accept class names only; never insert caller-provided HTML.
        const classes = String(value).trim().split(/\s+/).filter(token =>
            /^(?:fa|fas|far|fab|fa-[a-z0-9-]+)$/.test(token));
        if (!classes.some(token => /^(?:fa|fas|far|fab|fa-solid|fa-regular|fa-brands)$/.test(token))) {
            classes.unshift('fa-solid');
        }
        return classes;
    }
    function render(data) {
        const options = Array.isArray(data.options) ? data.options : [];
        if (!options.length || !Number.isFinite(data.x) || !Number.isFinite(data.y)) { root.hidden = true; return; }
        const selected = Math.max(0, Math.min(options.length - 1, (Number(data.selected) || 1) - 1));
        const start = Math.max(0, Math.min(selected - 1, options.length - 3));
        const end = Math.min(options.length, start + 3);
        const nextSignature = JSON.stringify([data.id, selected, options]);
        if (nextSignature !== signature) {
            signature = nextSignature;
            rows.replaceChildren();
            for (let index = start; index < end; index++) {
                const option = options[index];
                const row = document.createElement('div');
                row.className = `row${index === selected ? ' selected' : ''}${Math.abs(index - selected) > 1 ? ' row-distant' : ''}${option.disabled ? ' disabled' : ''}`;
                const marker = document.createElement('div');
                marker.className = 'marker';
                if (index === selected) {
                    const key = document.createElement('span');
                    key.textContent = 'E';
                    marker.append(key);
                }
                const label = document.createElement('div');
                label.className = 'label';
                if (option.icon) {
                    const icon = document.createElement('span');
                    icon.className = 'icon';
                    const glyph = document.createElement('i');
                    glyph.classList.add(...iconClasses(option.icon));
                    glyph.setAttribute('aria-hidden', 'true');
                    icon.append(glyph);
                    label.append(icon);
                }
                label.append(document.createTextNode(String(option.label || 'Interact')));
                row.append(marker, label);
                rows.append(row);
            }
        }
        root.hidden = false;
        switchHint.hidden = !(data.pointCount > 1);
        const rowHeight = rows.firstElementChild.offsetHeight;
        // The selected E marker stays on the world coordinate while the list scrolls.
        const left = Math.min(innerWidth - root.offsetWidth - 10, Math.max(10, data.x * innerWidth - 9));
        const top = Math.min(innerHeight - root.offsetHeight - 12, Math.max(12, data.y * innerHeight - (selected - start) * rowHeight - rowHeight / 2));
        root.style.left = `${left}px`;
        root.style.top = `${top}px`;
    }
    window.addEventListener('message', ({ data }) => {
        if (!data || typeof data !== 'object') return;
        if (data.action === 'hide') { root.hidden = true; return; }
        if (data.action === 'show') { lastMessage = Date.now(); render(data); }
    });
    // A stopped/restarting resource cannot leave a stale prompt on screen.
    setInterval(() => { if (Date.now() - lastMessage > 1000) root.hidden = true; }, 500);
})();
