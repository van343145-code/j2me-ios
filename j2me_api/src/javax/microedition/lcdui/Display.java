package javax.microedition.lcdui;

import javax.microedition.lcdui.event.EventQueue;
import javax.microedition.lcdui.event.Event;
import javax.microedition.lcdui.event.CanvasEvent;
import javax.microedition.lcdui.event.RunnableEvent;
import javax.microedition.midlet.MIDlet;

/**
 * J2ME Display — manages the current Displayable and render loop.
 * Analogous to J2ME-Loader's Display.
 */
public class Display {
    private static Display instance;
    private volatile Displayable current;
    private volatile boolean running;
    private static final EventQueue eventQueue = new EventQueue();
    private MIDlet currentMIDlet;

    // Screen dimensions (configurable via system properties)
    private static int screenWidth = 240;
    private static int screenHeight = 320;

    static {
        String w = System.getProperty("j2me.screen.width");
        String h = System.getProperty("j2me.screen.height");
        if (w != null) try { screenWidth = Integer.parseInt(w); } catch (Exception e) {}
        if (h != null) try { screenHeight = Integer.parseInt(h); } catch (Exception e) {}
    }

    private Display() {
    }

    public static synchronized Display getDisplay(MIDlet midlet) {
        if (instance == null) {
            instance = new Display();
        }
        if (midlet != null) {
            instance.currentMIDlet = midlet;
        }
        return instance;
    }

    public synchronized void setCurrent(Displayable d) {
        if (d == null) return;
        Displayable old = current;
        if (d instanceof Alert && old != d && ((Alert) d).nextDisplayable == null) {
            ((Alert) d).nextDisplayable = old instanceof Alert ? ((Alert) old).nextDisplayable : old;
        }
        current = d;

        boolean resized = (d.width != screenWidth || d.height != screenHeight);
        d.width = screenWidth;
        d.height = screenHeight;
        if (resized) {
            try { d.sizeChanged(screenWidth, screenHeight); } catch (Throwable ignored) {}
        }

        if (d instanceof Canvas) {
            // Pass canvas commands to native (for soft-key display)
            java.util.ArrayList<Command> cmds = d.getCommands();
            NativeBridge.formBegin("", 0); // reset command buffer
            for (int i = 0; i < cmds.size(); i++) {
                Command c = cmds.get(i);
                NativeBridge.formAddCommand(c.getLabel(), c.getCommandType(), c.getPriority(), i);
            }
            NativeBridge.showCanvas();
            Canvas canvas = (Canvas) d;
            canvas.initContext();
            canvas.showNotify();
            canvas.forceFullRepaint();
        } else {
            refresh(d);
        }

        if (old instanceof Canvas && old != d && current != old) {
            ((Canvas) old).hideNotify();
            // Keep the canvas graphics context for background game threads.
        }
    }

    synchronized void refresh(Displayable d) {
        if (d != current) return;
        if (d instanceof Form) {
            ((Form) d).showNative();
        } else if (d instanceof List) {
            ((List) d).showNative();
        } else if (d instanceof TextBox) {
            ((TextBox) d).showNative();
        } else if (d instanceof Alert) {
            ((Alert) d).showNative();
        }
    }

    public synchronized void setCurrent(Alert alert, Displayable nextDisplayable) {
        alert.nextDisplayable = nextDisplayable;
        setCurrent(alert);
    }

    private synchronized void dismissAlert(Alert alert) {
        if (current == alert && alert.nextDisplayable != null) {
            Displayable next = alert.nextDisplayable;
            alert.nextDisplayable = null;
            setCurrent(next);
        }
    }

    public Displayable getCurrent() {
        return current;
    }

    public void callSerially(Runnable r) {
        if (r != null) {
            Display.eventQueue.postEvent(RunnableEvent.getInstance(r));
        }
    }

    /**
     * Post an event to the event queue (analogous to J2ME-Loader's Display.postEvent).
     */
    public static void postEvent(Event event) {
        Display.eventQueue.postEvent(event);
    }

    public static EventQueue getEventQueue() {
        return eventQueue;
    }

    // --- Display capabilities (MIDP 2.0) ---

    public boolean isColor() { return true; }
    public int numColors() { return 16777216; } // 24-bit (2^24)
    public int numAlphaLevels() { return 256; } // 8-bit alpha
    public boolean flashBacklight(int duration) { return false; }
    public int getBestImageHeight(int imageType) { return 0; }
    public int getBestImageWidth(int imageType) { return 0; }
    public int getBorderStyle(boolean highlighted) {
        return highlighted ? Graphics.SOLID : Graphics.DOTTED;
    }
    public int getColor(int colorSpecifier) { return 0; }

    // --- Vibration ---

    public boolean vibrate(int duration) {
        if (duration < 0) throw new IllegalArgumentException();
        NativeBridge.vibrate(duration);
        return true;
    }

    // --- Screen size ---

    public static int getScreenWidth() { return screenWidth; }
    public static int getScreenHeight() { return screenHeight; }

    // --- Render loop ---

    /**
     * Run the render/event loop. Blocks until MIDlet calls notifyDestroyed().
     * Called by MIDletRunner after startApp().
     */
    public void runEventLoop() {
        running = true;
        eventQueue.startProcessing();
        System.out.println("[Display] Event loop started (" + screenWidth + "x" + screenHeight + ")");
        boolean wasInBackground = false;

        while (running && !MIDlet.isDestroyRequested()) {
            // 0. Check if native side requested stop (e.g. user pressed Back)
            if (NativeBridge.isStopRequested()) {
                System.out.println("[Display] Native stop requested, exiting event loop");
                MIDlet.requestDestroy();
                break;
            }

            // 1. Poll native input events and post to EventQueue
            int[] nativeEvent;
            while ((nativeEvent = NativeBridge.pollInputEvent()) != null) {
                try {
                    int type = nativeEvent[0];
                    if (type == 0 && nativeEvent[1] == 0 && nativeEvent[2] == 0) {
                        // iOS foreground wake up / unlock event: force immediate repaint
                        if (current instanceof Canvas) {
                            ((Canvas) current).forceFullRepaint();
                        }
                    }
                    if (type <= 2 && current instanceof Canvas) {
                        // Pointer event → post CanvasEvent
                        Canvas c = (Canvas) current;
                        int ceType = type == 0 ? CanvasEvent.POINTER_PRESSED :
                                     type == 1 ? CanvasEvent.POINTER_DRAGGED : CanvasEvent.POINTER_RELEASED;
                        Display.eventQueue.postEvent(CanvasEvent.getInstance(c, ceType, 0, (float)nativeEvent[1], (float)nativeEvent[2]));
                    } else if (type >= 3 && type <= 5 && current instanceof Canvas) {
                        // Key event → post CanvasEvent
                        Canvas c = (Canvas) current;
                        int ceType = type == 3 ? CanvasEvent.KEY_PRESSED :
                                     type == 4 ? CanvasEvent.KEY_RELEASED : CanvasEvent.KEY_REPEATED;
                        Display.eventQueue.postEvent(CanvasEvent.getInstance(c, ceType, nativeEvent[3]));
                    } else if (type == 10) {
                        int cmdId = nativeEvent[3];
                        Displayable target = current;
                        Command command = target == null ? null : target.getCommandAt(cmdId);
                        if (target instanceof Alert && command == null && cmdId == 0
                                && target.getCommands().isEmpty()) {
                            dismissAlert((Alert) target);
                        } else if (command != null) {
                            if (target instanceof TextBox) ((TextBox) target).syncFromNative();
                            if (target instanceof Form) ((Form) target).syncFromNative();
                            target.fireCommandAction(command);
                        }
                    } else if (type == 11 && current instanceof List) {
                        ((List) current).handleListSelect(nativeEvent[3]);
                    } else if (type == 12 && current instanceof Alert) {
                        dismissAlert((Alert) current);
                    } else if (type == 13 && current instanceof List) {
                        ((List) current).setSelectedIndex(nativeEvent[3], true);
                    } else if (type == 14 && current instanceof Form) {
                        ((Form) current).syncFromNative();
                    }
                } catch (Throwable t) {
                    System.out.println("[Display] Error handling input event: " + t);
                    t.printStackTrace();
                }
            }

            // 2. Handle resumeRequest — call startApp() again
            if (MIDlet.isResumeRequested() && currentMIDlet != null) {
                try {
                    currentMIDlet.callStartApp();
                } catch (Exception e) {
                    System.out.println("[Display] resumeRequest startApp error: " + e.getMessage());
                }
            }

            // 3. Repaint if needed (Canvas only)
            boolean inBg = false;
            try { inBg = NativeBridge.isBackground(); } catch (Throwable ignored) {}
            if (current instanceof Canvas) {
                Canvas canvas = (Canvas) current;
                if (!inBg && wasInBackground) {
                    // Just woke up or entered foreground: force immediate full repaint!
                    canvas.forceFullRepaint();
                } else if (inBg) {
                    canvas.flushTrailingRepaintIfNeeded();
                }
            }
            wasInBackground = inBg;

            // Sleep cleanly: 60ms in background (~16 wakeups/sec, eliminates iOS EXC_RESOURCE WAKEUPS kill!)
            // and 8ms in foreground for smooth, responsive native input polling.
            try {
                if (!MIDlet.isDestroyRequested()) {
                    Thread.sleep(inBg ? 60 : 8);
                }
            } catch (InterruptedException e) {
                if (NativeBridge.isStopRequested() || MIDlet.isDestroyRequested()) {
                    break;
                }
            }
        }

        eventQueue.stopProcessing();

        // Destroy current Canvas context to release native CGBitmapContext memory
        if (current instanceof Canvas) {
            ((Canvas) current).hideNotify();
            ((Canvas) current).destroyContext();
        }
        current = null;
        currentMIDlet = null;
        instance = null; // Reset for next MIDlet launch
        System.out.println("[Display] Event loop stopped");
    }

    /**
     * Stop the event loop.
     */
    public void stopEventLoop() {
        running = false;
    }
}
