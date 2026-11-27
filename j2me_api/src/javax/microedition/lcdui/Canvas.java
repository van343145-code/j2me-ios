package javax.microedition.lcdui;

import javax.microedition.lcdui.event.Event;
import javax.microedition.lcdui.event.EventFilter;

/**
 * J2ME Canvas — the main class for custom rendering in MIDlets.
 * Implements thread-safe paint and event pipeline matching J2ME-Loader ("Chơi game tuổi thơ").
 */
public abstract class Canvas extends Displayable {
    // Game action constants
    public static final int UP = 1;
    public static final int DOWN = 6;
    public static final int LEFT = 2;
    public static final int RIGHT = 5;
    public static final int FIRE = 8;
    public static final int GAME_A = 9;
    public static final int GAME_B = 10;
    public static final int GAME_C = 11;
    public static final int GAME_D = 12;

    // Key code constants (negative values for special keys, as per J2ME spec)
    public static final int KEY_UP = -1;
    public static final int KEY_DOWN = -2;
    public static final int KEY_LEFT = -3;
    public static final int KEY_RIGHT = -4;
    public static final int KEY_FIRE = -5;
    public static final int KEY_SOFT_LEFT = -6;
    public static final int KEY_SOFT_RIGHT = -7;
    public static final int KEY_CLEAR = -8;
    public static final int KEY_SEND = -10;
    public static final int KEY_END = -11;

    public static final int KEY_NUM0 = 48;
    public static final int KEY_NUM1 = 49;
    public static final int KEY_NUM2 = 50;
    public static final int KEY_NUM3 = 51;
    public static final int KEY_NUM4 = 52;
    public static final int KEY_NUM5 = 53;
    public static final int KEY_NUM6 = 54;
    public static final int KEY_NUM7 = 55;
    public static final int KEY_NUM8 = 56;
    public static final int KEY_NUM9 = 57;
    public static final int KEY_STAR = 42;
    public static final int KEY_POUND = 35;

    protected Canvas() { }
    protected Canvas(boolean fullScreen) { this.fullScreen = fullScreen; }

    private long nativeContext;
    private Graphics graphics;
    private boolean fullScreen = false;
    private final Object paintLock = new Object();
    private final PaintEvent paintEvent = new PaintEvent();

    // Helper Rect class matching J2ME-Loader Rect
    private static class Rect {
        int left, top, right, bottom;

        Rect() {}
        Rect(int l, int t, int r, int b) {
            left = l; top = t; right = r; bottom = b;
        }

        void setEmpty() {
            left = top = right = bottom = 0;
        }

        boolean isEmpty() {
            return left >= right || top >= bottom;
        }
    }

    /**
     * PaintEvent implements Event and EventFilter, exactly matching J2ME-Loader.
     * All repaints and dirty rect accumulations are serialized on paintEvent.clip.
     */
    private static final long BG_FRAME_INTERVAL_MS = 250L; // ~4 FPS cool pace in background / hidden tabs
    private volatile boolean pendingBgFlush = false;
    private long bgRepaintWindowStart = 0L;
    private int bgRepaintWindowCount = 0;

    private static boolean isRenderThrottled() {
        try {
            return NativeBridge.isBackground() || !NativeBridge.isSlotRenderActive();
        } catch (Throwable ignored) {
            return false;
        }
    }

    private class PaintEvent extends Event implements EventFilter {
        final Rect clip = new Rect();
        boolean isPending;
        private int enqueued = 0;

        @Override
        public synchronized void process() {
            if (!isShown()) {
                return;
            }
            boolean throttled = isRenderThrottled();

            int l, t, r, b;
            synchronized (clip) {
                isPending = false;
                pendingBgFlush = false;
                l = clip.left;
                t = clip.top;
                r = clip.right;
                b = clip.bottom;
                clip.setEmpty();
            }

            if (l >= r || t >= b) {
                return;
            }

            if (throttled) {
                limitBgFps();
            }

            synchronized (paintLock) {
                if (nativeContext == 0) initContext();
                if (graphics == null) return;
                graphics.reset(l, t, r - l, b - t);
                try {
                    // Run paint() even when throttled (screen CG draw calls are no-ops in C, while offscreen MutableImages and animation ticks continue)
                    paint(graphics);
                } catch (Throwable e) {
                    System.out.println("[Canvas] Warning: exception in paint(): " + e);
                }
                if (!throttled) {
                    NativeBridge.flushToScreen(nativeContext);
                }
            }
        }

        @Override
        public void recycle() {
        }

        @Override
        public void enterQueue() {
            enqueued++;
        }

        @Override
        public void leaveQueue() {
            enqueued--;
        }

        @Override
        public boolean placeableAfter(Event event) {
            return event != this;
        }

        @Override
        public boolean accept(Event event) {
            return event == this;
        }

        private boolean invalidateClip(Canvas canvas, int l, int t, int r, int b) {
            if (l < 0) l = 0;
            if (t < 0) t = 0;
            if (r > canvas.width) r = canvas.width;
            if (b > canvas.height) b = canvas.height;
            if (l >= r || t >= b) return false;

            boolean empty = clip.left >= clip.right || clip.top >= clip.bottom;
            if (empty) {
                clip.left = l;
                clip.top = t;
                clip.right = r;
                clip.bottom = b;
            } else {
                if (clip.left > l) clip.left = l;
                if (clip.top > t) clip.top = t;
                if (clip.right < r) clip.right = r;
                if (clip.bottom < b) clip.bottom = b;
            }
            return clip.left < clip.right && clip.top < clip.bottom;
        }
    }

    // FPS limiting (J2ME NST default 30 FPS + live native override)
    private static int fpsLimit = 30;
    private long lastFrameTime = System.currentTimeMillis();

    public static void setLimitFps(int fps) {
        Canvas.fpsLimit = fps >= 0 ? fps : 30;
    }

    public static int getLimitFps() {
        return fpsLimit;
    }

    private int effectiveFpsLimit() {
        try {
            int dyn = NativeBridge.getDynamicFpsLimit();
            if (dyn >= 0) return dyn;
        } catch (Throwable ignored) {}
        return fpsLimit;
    }

    private void limitFps() {
        int lim = effectiveFpsLimit();
        if (lim <= 0) return;
        try {
            long millis = (1000L / lim) - (System.currentTimeMillis() - lastFrameTime);
            if (millis > 0) Thread.sleep(millis);
        } catch (InterruptedException ignored) {}
        lastFrameTime = System.currentTimeMillis();
    }

    private void limitBgFps() {
        try {
            long millis = BG_FRAME_INTERVAL_MS - (System.currentTimeMillis() - lastFrameTime);
            if (millis > 0) Thread.sleep(millis);
        } catch (InterruptedException ignored) {}
        lastFrameTime = System.currentTimeMillis();
    }

    /**
     * Flush any trailing background repaint queued during throttled frame window (matches trailing-frame scheduling).
     */
    void flushTrailingRepaintIfNeeded() {
        if (!isShown() || !pendingBgFlush) return;
        long now = System.currentTimeMillis();
        if (now - lastFrameTime < BG_FRAME_INTERVAL_MS) return;
        boolean post;
        synchronized (paintEvent.clip) {
            pendingBgFlush = false;
            post = (paintEvent.clip.left < paintEvent.clip.right && paintEvent.clip.top < paintEvent.clip.bottom) && !paintEvent.isPending;
            if (post) {
                paintEvent.isPending = true;
            }
        }
        if (post) {
            Display.postEvent(paintEvent);
        }
    }

    /**
     * The abstract paint method — MIDlets override this.
     */
    protected abstract void paint(Graphics g);

    /**
     * Request a repaint of the entire canvas.
     */
    public void repaint() {
        repaint(0, 0, width, height);
    }

    public void repaint(int x, int y, int w, int h) {
        if (!isShown()) return;
        boolean throttled = isRenderThrottled();
        if (!throttled) {
            limitFps();
        } else {
            // Anti-spin guard for games that rely on repaint()/serviceRepaints() for frame pacing:
            // normal 25-30 FPS games (like NSO) never trigger this, while spin loops are capped
            // below iOS background CPU watchdog limits.
            long nowMs = System.currentTimeMillis();
            if (nowMs - bgRepaintWindowStart >= 1000L) {
                bgRepaintWindowStart = nowMs;
                bgRepaintWindowCount = 1;
            } else if (++bgRepaintWindowCount > 60) {
                try { Thread.sleep(12L); } catch (InterruptedException ignored) {}
            }
        }
        boolean post;
        synchronized (paintEvent.clip) {
            boolean hasDirty = paintEvent.invalidateClip(this, x, y, x + w, y + h);
            if (!hasDirty) return;
            if (throttled && (System.currentTimeMillis() - lastFrameTime < BG_FRAME_INTERVAL_MS)) {
                pendingBgFlush = true;
                return;
            }
            post = !paintEvent.isPending;
            if (post) {
                paintEvent.isPending = true;
            }
        }
        if (post) {
            Display.postEvent(paintEvent);
        }
    }

    public void forceFullRepaint() {
        if (!isShown()) return;
        synchronized (paintEvent.clip) {
            pendingBgFlush = false;
            paintEvent.invalidateClip(this, 0, 0, width, height);
            paintEvent.isPending = true;
        }
        Display.postEvent(paintEvent);
    }

    /**
     * Process all pending repaints synchronously.
     * Blocks until paint() completes using EventQueue's callbackLock
     * to ensure serialized access (matching J2ME-Loader behavior).
     */
    public void serviceRepaints() {
        if (!isShown()) return;
        if (isRenderThrottled()) {
            return;
        }
        Display.getEventQueue().serviceRepaints(paintEvent);
    }

    public void setFullScreenMode(boolean mode) {
        this.fullScreen = mode;
    }

    // --- Internal rendering ---

    /**
     * Initialize the offscreen context. Called when canvas becomes current.
     */
    void initContext() {
        if (nativeContext == 0) {
            nativeContext = NativeBridge.createContext(width, height);
            graphics = new Graphics(nativeContext, width, height);
        }
    }

    // GameCanvas — copy offscreen buffer to Canvas context and flush to screen.
    // Synchronized on paintLock to prevent concurrent CGContext access.
    public void flushBuffer(Image image, int x, int y, int width, int height) {
        if (!isShown()) return;
        if (width <= 0 || height <= 0 ||
                x + width < 0 || y + height < 0 ||
                x >= this.width || y >= this.height) {
            return;
        }
        if (isRenderThrottled()) {
            limitBgFps();
            return;
        }
        limitFps();
        synchronized (paintLock) {
            if (nativeContext == 0) initContext();
            if (graphics != null) {
                graphics.reset(0, 0, this.width, this.height);
                graphics.drawImage(image, 0, 0, Graphics.LEFT | Graphics.TOP);
                NativeBridge.flushToScreen(nativeContext);
            }
        }
    }

    // ExtendedImage (Siemens) — copy image to Canvas context at position and flush.
    public void flushBuffer(Image image, int x, int y) {
        if (!isShown()) return;
        if (isRenderThrottled()) {
            limitBgFps();
            return;
        }
        limitFps();
        synchronized (paintLock) {
            if (nativeContext == 0) initContext();
            if (graphics != null) {
                graphics.reset(0, 0, this.width, this.height);
                graphics.drawImage(image, x, y, Graphics.LEFT | Graphics.TOP);
                NativeBridge.flushToScreen(nativeContext);
            }
        }
    }

    /**
     * Compatibility delegation to PaintEvent.process()
     */
    public void doPaint() {
        paintEvent.process();
    }

    void destroyContext() {
        synchronized (paintLock) {
            if (nativeContext != 0) {
                NativeBridge.destroyContext(nativeContext);
                nativeContext = 0;
                graphics = null;
            }
        }
    }

    // --- Capabilities ---

    public boolean hasPointerEvents() { return true; }
    public boolean hasPointerMotionEvents() { return true; }
    public boolean hasRepeatEvents() { return true; }
    public boolean isDoubleBuffered() { return true; }

    // --- Input ---

    protected void keyPressed(int keyCode) { }
    protected void keyReleased(int keyCode) { }
    protected void keyRepeated(int keyCode) { }
    protected void pointerPressed(int x, int y) { }
    protected void pointerReleased(int x, int y) { }
    protected void pointerDragged(int x, int y) { }
    protected void showNotify() { }
    protected void hideNotify() { }

    // Methods called by CanvasEvent.process() (matching J2ME-Loader's Canvas API)
    public void doKeyPressed(int keyCode) { postKeyPressed(keyCode); }
    public void doKeyReleased(int keyCode) { postKeyReleased(keyCode); }
    public void doKeyRepeated(int keyCode) { postKeyRepeated(keyCode); }

    public void postKeyPressed(int keyCode) { keyPressed(keyCode); }
    public void postKeyReleased(int keyCode) { keyReleased(keyCode); }
    public void postKeyRepeated(int keyCode) { keyRepeated(keyCode); }
    public void pointerPressed(int pointer, float x, float y) { pointerPressed(Math.round(x), Math.round(y)); }
    public void pointerDragged(int pointer, float x, float y) { pointerDragged(Math.round(x), Math.round(y)); }
    public void pointerReleased(int pointer, float x, float y) { pointerReleased(Math.round(x), Math.round(y)); }
    public void doShowNotify() { showNotify(); }
    public void doHideNotify() { hideNotify(); }
    public void doSizeChanged(int w, int h) { sizeChanged(w, h); }

    // Public dispatch — called from Display event loop
    public void dispatchPointerEvent(int type, int x, int y) {
        switch (type) {
            case 0: pointerPressed(x, y); break;
            case 1: pointerDragged(x, y); break;
            case 2: pointerReleased(x, y); break;
        }
    }

    public void dispatchKeyEvent(int type, int keyCode) {
        switch (type) {
            case 3: keyPressed(keyCode); break;
            case 4: keyReleased(keyCode); break;
            case 5: keyRepeated(keyCode); break;
        }
    }

    public int getGameAction(int keyCode) {
        switch (keyCode) {
            case KEY_UP: case KEY_NUM2: return UP;
            case KEY_DOWN: case KEY_NUM8: return DOWN;
            case KEY_LEFT: case KEY_NUM4: return LEFT;
            case KEY_RIGHT: case KEY_NUM6: return RIGHT;
            case KEY_FIRE: case KEY_NUM5: return FIRE;
            case KEY_NUM7: return GAME_A;
            case KEY_NUM9: return GAME_B;
            case KEY_STAR: return GAME_C;
            case KEY_POUND: return GAME_D;
            default: return 0;
        }
    }

    public int getKeyCode(int gameAction) {
        switch (gameAction) {
            case UP: return KEY_NUM2;
            case DOWN: return KEY_NUM8;
            case LEFT: return KEY_NUM4;
            case RIGHT: return KEY_NUM6;
            case FIRE: return KEY_NUM5;
            default: return 0;
        }
    }

    public String getKeyName(int keyCode) {
        return "KEY_" + keyCode;
    }
}
