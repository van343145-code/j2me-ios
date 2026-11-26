  (function() {
    'use strict';

    // 'stretch' = fill entire viewport (may distort)
    // 'fit'     = keep aspect ratio, centered with black bars
    var _scaleMode = 'stretch';
    var _lastApplied = '';

    function applyCanvasScale() {
      var canvas = document.getElementById('canvas');
      if (!canvas) return;

      var vw = window.innerWidth, vh = window.innerHeight;
      // When rotated 90°, the canvas logical W/H are swapped relative to the viewport
      var cw = _rotation ? (canvas.height || 320) : (canvas.width  || 240);
      var ch = _rotation ? (canvas.width  || 240) : (canvas.height || 320);
      var w, h, top, left, tf;

      if (_scaleMode === 'fit' && cw > 0 && ch > 0) {
        var scale = Math.min(vw / cw, vh / ch);
        var fw = Math.floor(cw * scale);
        var fh = Math.floor(ch * scale);
        // When rotated -90deg, the CSS element's width/height map to the
        // viewport's height/width respectively. Swap so the rotated output
        // fills the correctly-scaled region.
        w = (_rotation ? fh : fw) + 'px';
        h = (_rotation ? fw : fh) + 'px';
        top = '50%'; left = '50%';
        tf = _rotation
          ? 'translate(-50%,-50%) rotate(-90deg)'
          : 'translate(-50%,-50%)';
      } else {
        // Stretch: fill the entire viewport.
        // When rotated -90deg, swap w/h so the rotated canvas covers the screen.
        w = (_rotation ? vh : vw) + 'px';
        h = (_rotation ? vw : vh) + 'px';
        top = _rotation ? '50%' : '0px';
        left = _rotation ? '50%' : '0px';
        tf = _rotation ? 'translate(-50%,-50%) rotate(-90deg)' : '';
      }

      if (canvas.style.width !== w || canvas.style.height !== h ||
          canvas.style.top !== top || canvas.style.left !== left) {
        canvas.style.cssText = 'display:block;position:absolute;background:#000;image-rendering:pixelated;'
          + 'width:' + w + ' !important;height:' + h + ' !important;'
          + 'top:' + top + ';left:' + left + ';'
          + (tf ? 'transform:' + tf + ';' : '');
      }
      // Always dispatch canvasresize so the engine re-reads getBoundingClientRect().
      // This is critical when the WKWebView frame changes: the canvas CSS may stay
      // the same string value (e.g. '100vw') but its actual pixel rect has shifted.
      // Without this, the engine's cached canvasRect stays stale and touch coordinates
      // are mapped against the old position/size.
      try { canvas.dispatchEvent(new Event('canvasresize')); } catch(e) {}
    }

    var _applying = false;
    var _applyTimer = null;
    function safeApply() {
      if (_applying) return;
      _applying = true;
      applyCanvasScale();
      _applying = false;
      // WKWebView may animate window size changes; schedule additional
      // applications to catch the final size after the animation settles.
      clearTimeout(_applyTimer);
      _applyTimer = setTimeout(function() {
        _applying = true;
        applyCanvasScale();
        _applying = false;
      }, 350);
    }

    function resumeAllAudio() {
      var contexts = [window.AA, window._audioContext, window.audioContext];
      try {
        if (typeof MIDP !== 'undefined' && MIDP.playerContainer) {
          contexts.push(MIDP.playerContainer.audioCtx);
          if (MIDP.playerContainer.audio && MIDP.playerContainer.audio.synth) {
            contexts.push(MIDP.playerContainer.audio.synth.context);
          }
        }
      } catch(e) {}
      for (var i = 0; i < contexts.length; i++) {
        try {
          if (contexts[i] && contexts[i].state === 'suspended') {
            contexts[i].resume();
          }
        } catch(e) {}
      }
    }

    // Audio unlock strategy:
    // 1. Monkey-patch AudioContext to auto-resume + play silent buffer on creation
    // 2. On page load, create a hidden <audio> element that auto-plays silence,
    //    then connect it to any AudioContext via createMediaElementSource to force
    //    the context into 'running' state.
    // 3. Periodically poll and resume all AudioContexts until they are running.
    // 4. Fallback: resume on user gesture for strict environments.
    (function unlockAudio() {
      var OrigAC = window.AudioContext || window.webkitAudioContext;
      if (!OrigAC) return;

      var allContexts = [];

      function tryUnlock(ctx) {
        if (!ctx) return;
        // Play a 1-sample silent buffer
        try {
          var buf = ctx.createBuffer(1, 1, 22050);
          var src = ctx.createBufferSource();
          src.buffer = buf;
          src.connect(ctx.destination);
          src.start(0);
        } catch(e) {}
        if (ctx.state === 'suspended') ctx.resume().catch(function(){});
      }

      // Track all created AudioContexts
      var PatchedAC = function() {
        var ctx = new OrigAC();
        allContexts.push(ctx);
        tryUnlock(ctx);
        return ctx;
      };
      PatchedAC.prototype = OrigAC.prototype;
      window.AudioContext = PatchedAC;
      if (window.webkitAudioContext) window.webkitAudioContext = PatchedAC;

      // Aggressively poll: resume all known AudioContexts every 500ms for 30s
      var pollCount = 0;
      var pollTimer = setInterval(function() {
        pollCount++;
        var allRunning = true;
        // Collect known contexts
        var ctxs = allContexts.slice();
        if (window.AA && ctxs.indexOf(window.AA) === -1) ctxs.push(window.AA);
        try {
          if (typeof MIDP !== 'undefined' && MIDP.playerContainer && MIDP.playerContainer.audioCtx) {
            if (ctxs.indexOf(MIDP.playerContainer.audioCtx) === -1) ctxs.push(MIDP.playerContainer.audioCtx);
          }
        } catch(e) {}

        for (var i = 0; i < ctxs.length; i++) {
          if (ctxs[i] && ctxs[i].state === 'suspended') {
            allRunning = false;
            tryUnlock(ctxs[i]);
          }
        }
        if ((allRunning && ctxs.length > 0) || pollCount > 60) {
          clearInterval(pollTimer);
        }
      }, 500);

      // On user gesture: resume everything
      function onGesture() {
        var ctxs = allContexts.slice();
        if (window.AA && ctxs.indexOf(window.AA) === -1) ctxs.push(window.AA);
        try {
          if (typeof MIDP !== 'undefined' && MIDP.playerContainer) {
            if (MIDP.playerContainer.audioCtx && ctxs.indexOf(MIDP.playerContainer.audioCtx) === -1)
              ctxs.push(MIDP.playerContainer.audioCtx);
            if (MIDP.playerContainer.audio && MIDP.playerContainer.audio.synth &&
                MIDP.playerContainer.audio.synth.context)
              ctxs.push(MIDP.playerContainer.audio.synth.context);
          }
        } catch(e) {}
        for (var i = 0; i < ctxs.length; i++) {
          tryUnlock(ctxs[i]);
        }
      }
      ['touchstart','touchend','click','mousedown','keydown','pointerdown'].forEach(function(evt) {
        document.addEventListener(evt, onGesture, { capture: true });
      });
    })();

    window.addEventListener('load', function() {
      safeApply();
      var canvas = document.getElementById('canvas');
      if (canvas) {
        var mo = new MutationObserver(function() { safeApply(); });
        mo.observe(canvas, { attributes: true, attributeFilter: ['style'] });
      }
      // Hook showExitScreen: notify Swift instead of redirecting to index.html
      var hookInterval = setInterval(function() {
        if (typeof showExitScreen === 'function') {
          window.showExitScreen = function() {
            document.getElementById('exit-screen').style.display = 'block';
            if (typeof myflushAll === 'function') myflushAll();
            try {
              window.webkit.messageHandlers.j2me.postMessage({ type: 'exit' });
            } catch(e) {}
          };
          clearInterval(hookInterval);
        }
      }, 200);
    });
    window.addEventListener('resize', safeApply);

    function postBridgeMessage(message) {
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.j2me) {
          window.webkit.messageHandlers.j2me.postMessage(message);
        }
      } catch(e) {}
    }

    function reportLaunchError(error) {
      var message = error && error.message ? error.message : String(error);
      postBridgeMessage({ type: 'launchError', message: message });
    }

    var _engineReady;
    function _waitForEngineReady() {
      if (_engineReady) return _engineReady;

      var documentReady = new Promise(function(resolve) {
        if (document.readyState === 'complete') resolve();
        else document.addEventListener('DOMContentLoaded', resolve, { once: true });
      });
      var timeout;
      var deadline = new Promise(function(resolve, reject) {
        timeout = setTimeout(function() {
          reject(new Error('Trình giả lập mất quá nhiều thời gian để tải.'));
        }, 25000);
      });
      var engine = documentReady.then(function() {
        if (typeof loadingPromises === 'undefined' || typeof initFS === 'undefined') {
          throw new Error('Không tải được bộ chạy Java ME.');
        }
        return Promise.all(loadingPromises);
      }).then(function() {
        if (typeof CLASSES === 'undefined' || !CLASSES.java_lang_Object ||
            typeof JARStore === 'undefined' || typeof MIDP === 'undefined' ||
            typeof jvm === 'undefined' || typeof fs === 'undefined' ||
            !fs.exists('/') || !fs.exists('/Private')) {
          throw new Error('Không khởi tạo được bộ chạy Java ME.');
        }
        _hookScheduler();
        _hookSaveNotification();
        _hookSpeedControl();
      });
      _engineReady = Promise.race([engine, deadline]).finally(function() {
        clearTimeout(timeout);
      });
      return _engineReady;
    }

    function midletEntries(manifest) {
      return Object.keys(manifest).flatMap(function(key) {
        var match = /^MIDlet-([1-9]\d*)$/i.exec(key);
        if (!match) return [];
        var fields = manifest[key].split(',');
        var className = fields.pop().trim().replace(/\//g, '.');
        if (!fields.length || !className) return [];
        return [{ index: Number(match[1]), name: fields[0].trim() || className, className: className }];
      }).sort(function(first, second) { return first.index - second.index; });
    }

    function parseScreenSize(value) {
      var match = /^\s*(\d+)\s*[x,*]\s*(\d+)\s*$/i.exec(value || '');
      if (!match) return null;
      var width = Number(match[1]), height = Number(match[2]);
      return width > 0 && width <= 2048 && height > 0 && height <= 2048 ? [width, height] : null;
    }

    function applyGameScreen(manifest, screenSize, rotation) {
      var dimensions = parseScreenSize(screenSize);
      if (!dimensions && !screenSizeSet) {
        dimensions = parseScreenSize(manifest['Nokia-MIDlet-Original-Display-Size']) ||
          parseScreenSize(manifest['Nokia-MIDlet-Target-Display-Size']);
        if (!dimensions && /^landscape$/i.test(manifest['Nokia-MIDlet-App-Orientation'] || '')) {
          dimensions = [320, 240];
        }
        if (dimensions && !scaleModeSet) _scaleMode = 'fit';
      }
      if (dimensions) _setScreenSize(dimensions[0], dimensions[1]);
      if (rotation) _setRotation(true);
    }

    async function _openJar(bytes, fileName, screenSize, rotation, allowSelection) {
      if (bytes instanceof ArrayBuffer) bytes = new Uint8Array(bytes);
      if (!(bytes instanceof Uint8Array) || bytes.length < 4 ||
          bytes[0] !== 0x50 || bytes[1] !== 0x4b || bytes[2] !== 0x03 || bytes[3] !== 0x04) {
        throw new Error('Tệp JAR không đúng định dạng hoặc đã bị hỏng.');
      }
      await _waitForEngineReady();

      var jarData = bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
        ? bytes.buffer : bytes.slice().buffer;
      var registeredJars = JARStore.getjars();
      var jarIndex = registeredJars.length;
      Object.keys(MIDP.manifest).forEach(function(key) { delete MIDP.manifest[key]; });
      try {
        JARStore.addBuiltIn(fileName, jarData, false);
      } catch (error) {
        throw new Error('Không đọc được nội dung tệp JAR.');
      }
      var directory = registeredJars[jarIndex][1].directory;
      var midlets = midletEntries(MIDP.manifest);
      if (!midlets.length) {
        registeredJars.splice(jarIndex, 1);
        throw new Error('Tệp JAR thiếu khai báo MIDlet của game Java ME.');
      }

      if (typeof hideDownloadScreen === 'function') hideDownloadScreen();
      var className = midlets[0].className;
      if (allowSelection && midlets.length > 1) {
        postBridgeMessage({ type: 'choicePresented' });
        className = await new Promise(function(resolve) {
          showMIDletSelector(midlets, resolve);
        });
        postBridgeMessage({ type: 'choiceCompleted' });
      }
      if (!directory[className.replace(/\./g, '/') + '.class']) {
        registeredJars.splice(jarIndex, 1);
        throw new Error('Không tìm thấy lớp khởi động Java ' + className + ' trong tệp JAR.');
      }

      config.jars = fileName;
      config.midletClassName = className;
      applyGameScreen(MIDP.manifest, screenSize, rotation);
      var root = document.documentElement;
      var gameReadySent = false;
      function notifyGameReady() {
        if (gameReadySent) return;
        gameReadySent = true;
        observer.disconnect();
        clearTimeout(readyFallback);
        postBridgeMessage({ type: 'gameReady' });
      }
      var observer = new MutationObserver(function() {
        if (root.classList.contains('app-keypad-ready')) notifyGameReady();
      });
      observer.observe(root, { attributes: true, attributeFilter: ['class'] });
      var readyFallback = setTimeout(function() {
        notifyGameReady();
      }, 2800);
      try {
        jvm.startIsolate0(config.main, config.args);
        if (root.classList.contains('app-keypad-ready')) {
          notifyGameReady();
        }
      } catch (error) {
        observer.disconnect();
        clearTimeout(readyFallback);
        throw error;
      }
    }

    async function _openJarFromURL(url, fileName) {
      var response = await fetch(url);
      if (!response.ok) throw new Error('Không tải được tệp JAR (mã ' + response.status + ').');
      await _openJar(await response.arrayBuffer(), fileName || 'game.jar', null, false, true);
    }

    var screenSizeSet = false;
    var scaleModeSet = false;
    function _setScreenSize(w, h) {
      screenSizeSet = true;
      config.canvasSize = 'size-' + w + 'x' + h;
      lcdWidth = w; lcdHeight = h;
      var canvas = document.getElementById('canvas');
      if (canvas) {
        canvas.width = w; canvas.height = h;
        try { canvas.dispatchEvent(new Event('canvasresize')); } catch(e) {}
      }
      applyCanvasScale();
    }

    var _rotation = false;

    function _setRotation(enabled) {
      _rotation = !!enabled;
      // The engine's getCanvasRotation() reads the CSS class on #main to detect
      // rotation and apply the correct inverse transform to touch coordinates.
      // We must keep this class in sync with our CSS transform so that
      // getEventPoint() remaps touches correctly when rotation is active.
      var main = document.getElementById('main');
      if (main) {
        if (_rotation) {
          main.classList.add('rotate-left');    // signals -90deg to getCanvasRotation()
          main.classList.remove('rotate-right');
        } else {
          main.classList.remove('rotate-left');
          main.classList.remove('rotate-right');
        }
      }
      applyCanvasScale();
    }

    function _setMute(mute) {
      try {
        var contexts = [window.AA, window._audioContext, window.audioContext];
        for (var i = 0; i < contexts.length; i++) {
          var ctx = contexts[i];
          if (ctx && typeof ctx.suspend === 'function') {
            mute ? ctx.suspend() : ctx.resume();
          }
        }
      } catch(e) {}
    }

    function _getSaveData() {
      if (typeof SaveManager === 'undefined' || typeof JSZip === 'undefined') return Promise.resolve(null);
      if (typeof myflushAll === 'function') myflushAll();
      return new Promise(function(resolve) {
        SaveManager.exportSaveToZip(config.midletClassName || 'game', function(blob) {
          if (!blob) { resolve(null); return; }
          var r = new FileReader();
          r.onload = function() {
            resolve(btoa(new Uint8Array(r.result).reduce(function(d, b) { return d + String.fromCharCode(b); }, '')));
          };
          r.onerror = function() { resolve(null); };
          r.readAsArrayBuffer(blob);
        });
      });
    }

    function _loadSaveData(b64) {
      if (typeof SaveManager === 'undefined' || typeof JSZip === 'undefined') return;
      try {
        var raw = atob(b64), bytes = new Uint8Array(raw.length);
        for (var i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
        SaveManager.importSaveFromZip(new Blob([bytes], { type: 'application/zip' }), function(ok) {
          console.log('loadSaveData:', ok ? 'OK' : 'FAIL');
        });
      } catch(e) { console.error('loadSaveData error:', e); }
    }

    // Error forwarding to Swift
    window.addEventListener('error', function(e) {
      try {
        window.webkit.messageHandlers.j2me.postMessage({
          type: 'jsError',
          message: (e.message || String(e)) + ' (' + (e.filename || '') + ':' + (e.lineno || '') + ')'
        });
      } catch(err) {}
    });

    async function restoreGameSave() {
      try {
        var save = await fetch('/game/save.zip');
        if (save.ok) {
          var blob = await save.blob();
          var restored = await new Promise(function(resolve) {
            SaveManager.importSaveFromZip(blob, resolve);
          });
          if (!restored) console.warn('Không thể nạp dữ liệu lưu cũ, bỏ qua.');
        }
      } catch(e) {
        console.warn('Lỗi kiểm tra dữ liệu lưu:', e);
      }
    }

    async function readGameJar(base64Jar) {
      if (base64Jar && typeof base64Jar === 'string' && base64Jar.length > 0) {
        try {
          var raw = atob(base64Jar);
          var bytes = new Uint8Array(raw.length);
          for (var i = 0; i < raw.length; i++) {
            bytes[i] = raw.charCodeAt(i);
          }
          return bytes;
        } catch(e) {
          console.warn('Lỗi giải mã base64Jar, thử tải qua mạng:', e);
        }
      }

      var jar = await fetch('/game/current.jar');
      if (!jar.ok) throw new Error('Không đọc được tệp JAR từ ứng dụng (mã ' + jar.status + ').');
      return new Uint8Array(await jar.arrayBuffer());
    }

    // Restore this game's RMS before allowing the MIDlet to start.
    var launch;
    window.nsvLaunch = function(base64Jar) {
      if (!launch) {
        launch = Promise.all([_waitForEngineReady(), readGameJar(base64Jar)]).then(async function(results) {
          await restoreGameSave();
          await _openJar(results[1], 'game.jar', null, false, true);
        }).catch(function(error) {
          launch = null;
          reportLaunchError(error);
          throw error;
        });
      }
      return launch;
    };

    // Save state format: JSON { version: 1, saveData: <zip_b64>, screen: <png_b64> }
    // saveData = SaveManager ZIP (RecordStore contents)
    // screen   = current canvas snapshot (preview only, not restored)
    function _exportSaveState() {
      if (typeof SaveManager === 'undefined' || typeof JSZip === 'undefined') {
        try { window.webkit.messageHandlers.j2me.postMessage({ type: 'exportSaveStateComplete', success: false }); } catch(e) {}
        return;
      }

      // Step 1: force flush all dirty data to IndexedDB
      if (typeof myflushAll === 'function') myflushAll();

      // Step 2: export RecordStore as ZIP
      SaveManager.exportSaveToZip(config.midletClassName || 'game', function(zipBlob) {
        var zipB64 = null;
        function finish(zipB64) {
          // Step 3: bundle and return
          var bundle = JSON.stringify({ version: 1, saveData: zipB64 });
          var bundleB64 = btoa(unescape(encodeURIComponent(bundle)));
          try {
            window.webkit.messageHandlers.j2me.postMessage({
              type: 'exportSaveStateComplete', success: true, data: bundleB64
            });
          } catch(e) {}
        }

        if (!zipBlob) {
          finish(null);
          return;
        }
        var reader = new FileReader();
        reader.onload = function() {
          var zip64 = btoa(new Uint8Array(reader.result).reduce(function(d, b) { return d + String.fromCharCode(b); }, ''));
          finish(zip64);
        };
        reader.onerror = function() { finish(null); };
        reader.readAsArrayBuffer(zipBlob);
      });
    }

    function _importSaveState(b64) {
      try {
        if (typeof SaveManager === 'undefined' || typeof JSZip === 'undefined') throw new Error('Engine not ready');

        // Decode the bundle
        var bundle = JSON.parse(decodeURIComponent(escape(atob(b64))));
        if (!bundle || bundle.version !== 1 || !bundle.saveData) throw new Error('Invalid save state format');

        // Decode the ZIP and import RecordStore into IndexedDB
        var zipRaw = atob(bundle.saveData);
        var zipBytes = new Uint8Array(zipRaw.length);
        for (var i = 0; i < zipRaw.length; i++) zipBytes[i] = zipRaw.charCodeAt(i);
        var zipBlob = new Blob([zipBytes], { type: 'application/zip' });

        SaveManager.importSaveFromZip(zipBlob, function() {
          // RecordStore is now in IndexedDB — notify Swift to trigger reset+reload
          try { window.webkit.messageHandlers.j2me.postMessage({ type: 'importSaveStateComplete', success: true }); } catch(e) {}
        });
      } catch(err) {
        try { window.webkit.messageHandlers.j2me.postMessage({ type: 'importSaveStateComplete', success: false, error: err.message }); } catch(e) {}
      }
    }

    var _keyCodeMap = {
      'ArrowUp': -1, 'ArrowDown': -2, 'ArrowLeft': -3, 'ArrowRight': -4,
      'Enter': -5, 'OK': -5,
      'F1': -6, 'SoftLeft': -6, 'LSK': -6,
      'F2': -7, 'SoftRight': -7, 'RSK': -7,
      'Digit0': 48, '0': 48,
      'Digit1': 49, '1': 49,
      'Digit2': 50, '2': 50,
      'Digit3': 51, '3': 51,
      'Digit4': 52, '4': 52,
      'Digit5': 53, '5': 53,
      'Digit6': 54, '6': 54,
      'Digit7': 55, '7': 55,
      'Digit8': 56, '8': 56,
      'Digit9': 57, '9': 57,
      'KeyE': 42, 'Star': 42, '*': 42,
      'KeyR': 35, 'Pound': 35, 'Hash': 35, '#': 35
    };

    var _paused = false;
    var _savedQueue = null;

    function _pause() {
      if (_paused) return;
      _paused = true;
      _setMute(true);
      console.log('[iOS] Emulator paused');
    }

    function _resume() {
      if (!_paused) return;
      _paused = false;
      _setMute(false);
      // Kick the scheduler to process contexts that accumulated while paused
      if (typeof J2ME !== 'undefined' && J2ME.Scheduler && _origProcessRunningQueue) {
        _origProcessRunningQueue.call(J2ME.Scheduler, false);
      }
      console.log('[iOS] Emulator resumed');
    }

    // Intercept Scheduler.processRunningQueue to block when paused.
    // When paused, enqueue still adds contexts to runningQueue (that logic is
    // in Scheduler.enqueue before calling processRunningQueue), but we skip
    // processing so threads accumulate. On resume we call origProcess once
    // to drain the queue.
    var _schedReady = false;
    var _origProcessRunningQueue = null;
    function _hookScheduler() {
      if (_schedReady || typeof J2ME === 'undefined' || !J2ME.Scheduler) return;
      _schedReady = true;
      _origProcessRunningQueue = J2ME.Scheduler.processRunningQueue;
      J2ME.Scheduler.processRunningQueue = function(directExecution) {
        if (_paused) return;
        _origProcessRunningQueue.call(J2ME.Scheduler, directExecution);
      };
    }

    // Auto-save notification: when RecordStore data is synced to IndexedDB,
    // debounce and export the save data as ZIP, then notify the Swift layer
    // via the 'saveDataWritten' message so the native side can persist it.
    var _saveNotifyTimer = null;
    var _saveNotifyBusy = false;
    var _SAVE_NOTIFY_DELAY = 3000; // debounce: wait 3s after last write

    function _hookSaveNotification() {
      if (typeof fs === 'undefined' || typeof fs.setOnRecordStoreSynced !== 'function') return;
      fs.setOnRecordStoreSynced(function() {
        // Debounce: reset the timer on every sync that touches RecordStore
        if (_saveNotifyTimer) clearTimeout(_saveNotifyTimer);
        _saveNotifyTimer = setTimeout(_doSaveNotify, _SAVE_NOTIFY_DELAY);
      });
      console.log('[iOS] Save auto-notification hooked');
    }

    function _doSaveNotify() {
      _saveNotifyTimer = null;
      if (_saveNotifyBusy) return; // skip if a previous export is still running
      if (typeof SaveManager === 'undefined' || typeof JSZip === 'undefined') return;

      _saveNotifyBusy = true;
      SaveManager.exportSaveToZip(config.midletClassName || 'game', function(blob) {
        if (!blob) {
          _saveNotifyBusy = false;
          return;
        }
        var reader = new FileReader();
        reader.onload = function() {
          var b64 = btoa(new Uint8Array(reader.result).reduce(function(d, b) { return d + String.fromCharCode(b); }, ''));
          try {
            window.webkit.messageHandlers.j2me.postMessage({ type: 'saveDataWritten', data: b64 });
          } catch(e) {}
          _saveNotifyBusy = false;
        };
        reader.onerror = function() { _saveNotifyBusy = false; };
        reader.readAsArrayBuffer(blob);
      });
    }

    // ── Speed control ─────────────────────────────────────────────────────────
    //
    // Root cause analysis:
    //
    // 1. Thread.sleep hook may miss already-linked methods:
    //    findNativeMethodImplementation() caches Native[key] into methodInfo.fn
    //    at first call. Replacing Native[key] after linking has no effect.
    //    Fix: also patch methodInfo.fn directly after JVM starts.
    //
    // 2. Most J2ME games are time-based, not frame-count-based:
    //    They compute delta = System.currentTimeMillis() - lastTime and drive
    //    all animation/physics through that delta. Reducing Thread.sleep alone
    //    makes the loop iterate faster but each iteration sees a tiny real-time
    //    delta, so the game appears unchanged visually.
    //    Fix: maintain a virtual clock and override System.currentTimeMillis()
    //    so the Java world perceives time advancing at speedMultiplier × rate.
    //
    // Combined approach:
    //  • Virtual clock  → System.currentTimeMillis() returns scaled virtual time
    //  • Thread.sleep   → delay divided by multiplier (loop iterates faster)
    //  • Both together  → covers frame-based AND time-based game loops
    //
    var _speedMultiplier = 1.0;

    // Virtual clock state.
    // virtualNow() = _vcBase + (Date.now() - _vcRealBase) * _speedMultiplier
    var _vcBase     = Date.now(); // accumulated virtual ms at last speed change
    var _vcRealBase = Date.now(); // real ms at last speed change

    function _virtualNow() {
      return _vcBase + (Date.now() - _vcRealBase) * _speedMultiplier;
    }

    function _hookSpeedControl() {
      if (typeof Native === 'undefined') return;

      // ── System.currentTimeMillis ──────────────────────────────────────────
      // Override unconditionally so time-based games always see virtual time.
      Native["java/lang/System.currentTimeMillis.()J"] = function(addr) {
        return J2ME.returnLongValue(Math.round(_virtualNow()));
      };

      // ── Thread.sleep ──────────────────────────────────────────────────────
      // Replace the Native binding first (catches methods linked after this).
      var sleepImpl = function(addr, delayL, delayH) {
        var delay = J2ME.longToNumber(delayL, delayH);
        var scaledDelay = Math.max(0, Math.round(delay / _speedMultiplier));
        J2ME.asyncImpl(9 /* Kind.Void */, new Promise(function(resolve) {
          window.setTimeout(resolve, scaledDelay);
        }));
      };
      Native["java/lang/Thread.sleep.(J)V"] = sleepImpl;

      // Also patch methodInfo.fn if Thread.sleep was already linked before us.
      // This handles engines where Native[key] is cached at link time.
      try {
        var threadClass = J2ME.CLASSES.getClass('java/lang/Thread');
        if (threadClass) {
          var sleepInfo = threadClass.getMethodByNameString('sleep', '(J)V');
          if (sleepInfo && sleepInfo.fn) {
            sleepInfo.fn = sleepImpl;
          }
        }
      } catch(e) {}

      console.log('[iOS] Speed control hooked');
    }

    function _setSpeed(multiplier) {
      multiplier = Math.max(0.25, Math.min(multiplier, 8));

      // Commit accumulated virtual time before changing the multiplier so the
      // clock stays continuous: no jump or gap at the transition point.
      _vcBase     = _virtualNow();
      _vcRealBase = Date.now();
      _speedMultiplier = multiplier;

      // Update audio playback rate for all active players.
      if (typeof Media !== 'undefined' && Media.PlayerCache) {
        Object.keys(Media.PlayerCache).forEach(function(id) {
          var pc = Media.PlayerCache[id];
          if (!pc) return;
          // midimode 3: <audio> element
          if (pc.audio && typeof pc.audio.playbackRate !== 'undefined') {
            pc.audio.playbackRate = multiplier;
          }
          // midimode 4: AudioBufferSourceNode
          if (pc.source && pc.source.playbackRate) {
            pc.source.playbackRate.value = multiplier;
          }
        });
      }

      console.log('[iOS] Speed set to ' + multiplier + 'x');
    }

    window.j2me = {
      openJar: _openJar,
      openJarFromURL: _openJarFromURL,
      reset: function() { window.location.reload(); },
      pause: _pause,
      resume: _resume
    };

    window.j2meAPI = {
      setScreenSize: _setScreenSize,
      setMute: _setMute,
      getSaveData: _getSaveData,
      loadSaveData: _loadSaveData,
      exportSaveState: _exportSaveState,
      importSaveState: _importSaveState,
      setGameResize: function(v) { config.gameresize = v; },
      setCanvasSize: function(v) { config.canvasSize = v; },
      setScreenRotation: function(v) { config.screenRotation = v; },
      setConfig: function(k, v) { config[k] = v; },
      setScaleMode: function(mode) {
        scaleModeSet = true;
        _scaleMode = (mode === 'fit') ? 'fit' : 'stretch';
        applyCanvasScale();
      },
      getScaleMode: function() { return _scaleMode; },
      safeApply: safeApply,
      setRotation: _setRotation,
      pause: _pause,
      resume: _resume,
      setSpeed: _setSpeed,
      isPaused: function() { return _paused; },
      setParams: function(dict) {
        if (!dict || typeof dict !== 'object') return;
        for (var k in dict) {
          if (!dict.hasOwnProperty(k)) continue;
          var v = dict[k];
          config[k] = v;
          if (k === 'canvasSize' && v && v !== 'size-no') {
            try {
              var parts = v.split('-')[1].split('x');
              var w = parseInt(parts[0]), h = parseInt(parts[1]);
              if (w > 0 && h > 0) _setScreenSize(w, h);
            } catch(e) {}
          }
        }
      },
      /**
       * 各参数在引擎中的实际消费位置
          参数	消费位置	作用
          main	main-all.js:23325 jvm.startIsolate0(config.main, ...)	JVM 入口类，默认 com/sun/midp/main/MIDletSuiteLoader
          midletClassName	main-all.js:10367-10369 CommandState.restoreCommandState	告诉 JVM 启动哪个 MIDlet 类；由 JAR 的 MANIFEST.MF 自动解析
          args	main-all.js:10370-10373	传递给 MIDlet 的启动参数（最多 3 个）
          jars	main-all.js:23180-23181	要加载的 JAR 文件路径，冒号分隔多个
          jad	urlparams 中声明但当前代码未使用	JAD 描述文件路径（部分分支可能使用）
          localjar	main-all.js:23353-23381	从 IndexedDB 加载的本地 JAR 路径
          gamepad	main-all.js:24,23174	是否显示虚拟键盘，0=关闭
          gamepadSize	main-all.js:25-26,46-47	虚拟键盘尺寸 CSS 类名
          canvasSize	main-all.js:10207-10226 updateCanvas()	固定 canvas 内部分辨率，格式 size-WxH 或 size-no
          gameresize	main-all.js:10244-10295 updateCanvas()	CSS 缩放倍率：resize-0x5/resize-0x75/resize-1/resize-1x5/resize-2/resize-2x5/resize-3
          screenRotation	main-all.js:33-77	屏幕旋转：left（逆时针90°）/ right（顺时针90°）
          autosize	main-all.js:10519,10160	1=canvas 跟随窗口自动调整，0=使用 #display 的固定尺寸
          fontSize	main-all.js:13051	J2ME 字体渲染大小（像素），默认按屏幕高度自动计算
          language	main-all.js:11271	UI 本地化语言，如 zh-CN、en-US，影响 MIDP 系统字符串
          platform	main-all.js:688	System.getProperty("microedition.platform") 返回值，默认 Nokia 平台串
          forceRuntimeCompilation	j2me.js:3571,3686,6436	强制 JIT 编译所有方法，调试用
          deferStartup	main-all.js:23293	延迟启动 JVM 的毫秒数（基准测试用）
          invokeThreshold	j2me.js:6908	方法调用次数阈值，超过后触发 JIT 编译
          backwardBranchThreshold	j2me.js:6909	后向跳转（循环）次数阈值，超过后触发 JIT
          customEmojiImageFormat	main-all.js:9495-9496	自定义 emoji 图片路径模板，NUM 替换为十六进制编号
          chRegisteredID	main-all.js:19826	Content Handler 注册 ID
          chRegisteredClassName	main-all.js:19827	Content Handler 注册类名
          icc_mcc/mnc/msisdn, network_mcc/mnc	urlparams 中声明	当前代码中未使用（可能是旧版功能残留）
          logConsole/logLevel	urlparams 中声明	当前代码中未使用
      */
      getParams: function() {
        var out = {};
        var keys = ['main','midletClassName','jars','jad','localjar','args',
          'gamepad','gamepadSize','canvasSize','gameresize','screenRotation',
          'autosize','fontSize','language','platform','forceRuntimeCompilation',
          'deferStartup','customEmojiImageFormat','chRegisteredID',
          'chRegisteredClassName','chRegisteredStorageID',
          'chRegisteredRegistrationMethod','invokeThreshold',
          'backwardBranchThreshold'];
        for (var i = 0; i < keys.length; i++) {
          if (config[keys[i]] !== undefined) out[keys[i]] = config[keys[i]];
        }
        return out;
      }
    };

    var pressedNativeKeys = new Set();

    function handleNativeMenuKey(key, code) {
      var selector = document.getElementById('midlet-selector-screen');
      var selecting = selector && selector._midletKeyHandler && selector.style.display !== 'none';
      var overlay = typeof isOverlayActive === 'function' && isOverlayActive();
      if (selecting || overlay) {
        var name = code === -5 ? 'Enter' : code === -6 ? 'F1' : code === -7 ? 'F2' :
          (code >= 48 && code <= 57 ? String.fromCharCode(code) : key);
        var event = new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true });
        if (selecting) selector._midletKeyHandler(event);
        else handleOverlayKeydown(event);
        return true;
      }

      var popup = document.getElementById('canvas-command-popup');
      if (popup && popup.style.display !== 'none') {
        if (code === -7) {
          popup.style.display = 'none';
          return true;
        }
        var choices = Array.from(popup.querySelectorAll('.canvas-command-item'));
        if (!choices.length) return false;
        var focus = choices.findIndex(function(item) { return item.classList.contains('focused'); });
        if (code === -5 || code === -6) {
          choices[Math.max(focus, 0)].click();
          return true;
        }
        if (code === -1 || code === -2) {
          if (focus !== -1) choices[focus].classList.remove('focused');
          var next = focus === -1 ? (code === -1 ? choices.length - 1 : 0) :
            (focus + (code === -1 ? -1 : 1) + choices.length) % choices.length;
          choices[next].classList.add('focused');
          choices[next].scrollIntoView({ block: 'nearest' });
        }
        return true;
      }
      if (code === -6 || code === -7) {
        var button = document.getElementById(code === -6 ? 'canvas-softkey-left' : 'canvas-softkey-right');
        if (button && typeof button.onclick === 'function' && button.style.visibility !== 'hidden') {
          button.click();
          return true;
        }
      }
      return false;
    }

    window.Input = {
      keyDown: function(key) {
        var code = _keyCodeMap[key];
        if (code === undefined || typeof MIDP === 'undefined' || pressedNativeKeys.has(code) || handleNativeMenuKey(key, code)) return;
        pressedNativeKeys.add(code);
        MIDP.sendKeyPress(code);
      },
      keyUp: function(key) {
        var code = _keyCodeMap[key];
        if (typeof MIDP !== 'undefined' && pressedNativeKeys.delete(code)) MIDP.sendKeyRelease(code);
      },
      rawKeyDown: function(code) {
        if (typeof code !== 'number' || typeof MIDP === 'undefined') return;
        if (handleNativeMenuKey(String(code), code)) return;
        if (pressedNativeKeys.has(code)) return;
        pressedNativeKeys.add(code);
        MIDP.sendKeyPress(code);
      },
      rawKeyUp: function(code) {
        if (typeof code !== 'number' || typeof MIDP === 'undefined') return;
        if (pressedNativeKeys.delete(code)) MIDP.sendKeyRelease(code);
      },
      rawKeyRepeat: function(code) {
        if (typeof code !== 'number' || typeof MIDP === 'undefined') return;
        if (typeof MIDP.sendKeyRepeat === 'function') {
          MIDP.sendKeyRepeat(code);
        } else {
          MIDP.sendKeyRelease(code);
          MIDP.sendKeyPress(code);
        }
      },
      releaseAll: function() {
        if (typeof MIDP === 'undefined') { pressedNativeKeys.clear(); return; }
        pressedNativeKeys.forEach(function(code) {
          try { MIDP.sendKeyRelease(code); } catch(e) {}
        });
        pressedNativeKeys.clear();
      }
    };

    // FPS limit & background throttle (matching J2ME NST cool-running defaults)
    var _nstFpsLimit = 30;
    var _nstInBackground = false;
    var _nstFilter = false;
    (function hookRafThrottle() {
      var origRAF = window.requestAnimationFrame;
      if (typeof origRAF !== 'function') return;
      var lastFrame = 0;
      window.requestAnimationFrame = function(cb) {
        var limit = _nstInBackground ? 4 : _nstFpsLimit;
        if (!limit || limit <= 0 || limit >= 60) {
          return origRAF.call(window, cb);
        }
        var minGap = 1000 / limit;
        var now = performance.now();
        var wait = Math.max(0, minGap - (now - lastFrame));
        if (wait <= 1) {
          lastFrame = now;
          return origRAF.call(window, cb);
        }
        return setTimeout(function() {
          lastFrame = performance.now();
          origRAF.call(window, cb);
        }, wait);
      };
    })();

    window.nstApplyConfig = function(opts) {
      if (!opts || typeof opts !== 'object') return;
      if (typeof opts.fpsLimit === 'number') {
        _nstFpsLimit = Math.max(0, Math.min(opts.fpsLimit, 120));
      }
      if (typeof opts.filter === 'boolean') {
        _nstFilter = opts.filter;
        var c = document.getElementById('canvas');
        if (c) c.style.imageRendering = _nstFilter ? 'auto' : 'pixelated';
      }
      if (typeof opts.touchEnabled === 'boolean') {
        var c2 = document.getElementById('canvas');
        if (c2) c2.style.pointerEvents = opts.touchEnabled ? 'auto' : 'none';
      }
      if (typeof opts.scaleMode === 'string') {
        scaleModeSet = true;
        _scaleMode = opts.scaleMode === 'stretch' ? 'stretch' : 'fit';
      }
      if (typeof opts.width === 'number' && typeof opts.height === 'number' && opts.width >= 64 && opts.height >= 64) {
        _setScreenSize(opts.width, opts.height);
      } else {
        safeApply();
      }
    };

    window.nstSetBackground = function(bg) {
      _nstInBackground = !!bg;
    };

    var _isTextEditing = false;
    function reportTextEditing() {
      var editing = isEditableKeyTarget(document.activeElement);
      if (editing === _isTextEditing) return;
      _isTextEditing = editing;
      try {
        window.webkit.messageHandlers.j2me.postMessage({ type: 'textEditing', active: editing });
      } catch(e) {}
    }
    document.addEventListener('focusin', reportTextEditing);
    document.addEventListener('focusout', function() { setTimeout(reportTextEditing, 0); });

    var tp = new URLSearchParams(window.location.search);
    if (tp.get('scale') === 'fit') {
      scaleModeSet = true;
      _scaleMode = 'fit';
    }

    // Swift launches the game once the system classes and file store are available.
    _waitForEngineReady().then(function() {
      console.log('[iOS] Engine ready, notifying Swift layer');
      postBridgeMessage({ type: 'ready' });
      if (tp.get('test') === '1') {
        return _openJarFromURL('VanTranidol_NokiaE6.jar', 'VanTranidol_NokiaE6.jar');
      }
    }).catch(reportLaunchError);
    window.nsvSetScaleMode = function(mode) {
      scaleModeSet = true;
      _scaleMode = mode;
      safeApply();
    };
    window.nsvSetScreenSize = function(w, h) {
      _setScreenSize(w, h);
      safeApply();
    };
    window.nsvTick = function() {
      if (typeof myflushAll === 'function') {
        try { myflushAll(); } catch(e) {}
      }
    };

  })();
