    document.addEventListener('touchmove', function(e) {
      var target = e.target;
      while (target && target !== document.body) {
        if (target.scrollHeight > target.clientHeight ||
            target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' ||
            target.contentEditable === 'true' || target.classList.contains('text-editor') ||
            target.closest('form[role="dialog"]')) return;
        target = target.parentElement;
      }
      e.preventDefault();
    }, { passive: false });
    var lastTouchEnd = 0;
    document.addEventListener('touchend', function(e) {
      var now = Date.now();
      if (now - lastTouchEnd <= 300) e.preventDefault();
      lastTouchEnd = now;
    }, false);
