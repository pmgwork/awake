// Installed by Awake (pmgwork.awake).
(function (config) {
    if ($.global.__awakeAE && !$.global.__awakeAE.dispose()) {
        throw new Error('Awake: wait for the current render to finish before reconnecting.');
    }
    var watched = [];
    var sequence = 0;
    var task = null;
    var lastWrite = 0;
    var lastActive = null;
    var source = new File(config.controlPath);
    var signal = new File(config.signalPath);
    var prefix = '__awakeAEStatus_' + config.token.replace(/-/g, '') + '_';
    function queue() { return app.project ? app.project.renderQueue : null; }
    function active() {
        var q = queue();
        if (!q) { return false; }
        for (var i = 1; i <= q.numItems; i++) {
            if (q.item(i).status === RQItemStatus.RENDERING) { return true; }
        }
        return false;
    }
    function publish() {
        var running = source.exists && active();
        var now = (new Date()).getTime();
        if (running === lastActive && signal.exists && now - lastWrite < 3000) { return; }
        if (!signal.open('w')) { throw new Error('Awake: allow scripts to write files in Adobe After Effects.'); }
        signal.write('{"token":"' + config.token + '","active":' + (running ? 'true' : 'false') + '}');
        signal.close();
        lastWrite = now;
        lastActive = running;
    }
    function invoke(callback) {
        if (typeof callback === 'function') { callback(); return; }
        if (typeof callback !== 'string' || !callback) { return; }
        var parts = callback.split('.');
        var owner = $.global;
        for (var i = 0; owner && i < parts.length - 1; i++) { owner = owner[parts[i]]; }
        var fn = owner ? owner[parts[parts.length - 1]] : null;
        if (typeof fn === 'function') { fn.call(owner); }
    }
    function safePublish() { try { publish(); } catch (error) { /* Never interrupt a render. */ } }
    function watch(item) {
        for (var i = 0; i < watched.length; i++) {
            if (watched[i].item === item && item.onStatusChanged === watched[i].name) { return; }
        }
        var previous = item.onStatusChanged;
        // Do not wrap an unknown callback expression that we cannot preserve.
        if (previous && typeof previous !== 'function' && !/^[A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)*$/.test(previous)) { return; }
        var name = prefix + (++sequence);
        $.global[name] = function () {
            safePublish();
            try { invoke(previous); } finally { safePublish(); }
        };
        item.onStatusChanged = name;
        watched.push({item: item, previous: previous, name: name});
    }
    function dispose() {
        var q = queue();
        if (q && q.rendering) { return false; }
        if (task !== null) { app.cancelTask(task); task = null; }
        // Reverse order also restores callbacks wrapped again by another script.
        for (var i = watched.length - 1; i >= 0; i--) {
            var restored = false;
            try {
                if (watched[i].item.onStatusChanged === watched[i].name) {
                    watched[i].item.onStatusChanged = watched[i].previous;
                    restored = true;
                }
            } catch (error) { restored = true; /* Item removed or project closed. */ }
            if (restored) { delete $.global[watched[i].name]; }
            else {
                // Another script may still reference this wrapper.
                (function (entry) { $.global[entry.name] = function () { invoke(entry.previous); }; }(watched[i]));
            }
        }
        watched = [];
        signal.remove();
        return true;
    }
    function tick() {
        safePublish();
        if (!source.exists) { dispose(); return; }
        var q = queue();
        if (q && !q.rendering) {
            var live = [];
            for (var i = 1; i <= q.numItems; i++) { live.push(q.item(i)); }
            for (var j = watched.length - 1; j >= 0; j--) {
                var found = false;
                for (var k = 0; k < live.length; k++) {
                    if (live[k] === watched[j].item) { found = true; break; }
                }
                if (!found) { delete $.global[watched[j].name]; watched.splice(j, 1); }
            }
            for (var n = 0; n < live.length; n++) {
                try { watch(live[n]); } catch (error) { /* Never interrupt editing. */ }
            }
        }
    }
    // Fail attachment visibly if AE's file-write preference is off.
    publish();
    $.global.__awakeAE = {tick: tick, dispose: dispose};
    task = app.scheduleTask('$.global.__awakeAE.tick()', 200, true);
    tick();
}(__AWAKE_CONFIG__));
