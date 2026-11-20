package javax.microedition.lcdui;

import java.util.ArrayList;

public class TextBox extends Screen {
    private String text;
    private int maxSize;
    private int constraints;

    public TextBox(String title, String text, int maxSize, int constraints) {
        setTitle(title);
        this.text = text != null ? text : "";
        this.maxSize = maxSize;
        this.constraints = constraints;
    }

    public String getString() { return text != null ? text : ""; }
    public void setString(String text) {
        String value = limitText(text);
        if (value.equals(this.text)) return;
        this.text = value;
        requestNativeRefresh();
    }

    void syncFromNative() {
        String value = NativeBridge.getTextBoxText();
        if (value != null && (constraints & TextField.UNEDITABLE) == 0) text = limitText(value);
    }

    private String limitText(String value) {
        if (value == null) return "";
        if (maxSize <= 0 || value.length() <= maxSize) return value;
        return value.substring(0, maxSize);
    }
    public int getMaxSize() { return maxSize; }
    public int setMaxSize(int maxSize) { this.maxSize = maxSize; return maxSize; }
    public int getConstraints() { return constraints; }
    public void setConstraints(int constraints) { this.constraints = constraints; }
    public int size() { return text != null ? text.length() : 0; }

    public void insert(String src, int position) {
        if (src == null) return;
        StringBuilder sb = new StringBuilder(text != null ? text : "");
        int pos = Math.max(0, Math.min(position, sb.length()));
        sb.insert(pos, src);
        this.text = sb.toString();
    }

    public void delete(int offset, int length) {
        if (text == null) return;
        StringBuilder sb = new StringBuilder(text);
        int start = Math.max(0, Math.min(offset, sb.length()));
        int end = Math.max(start, Math.min(start + length, sb.length()));
        if (start < end) {
            sb.delete(start, end);
            this.text = sb.toString();
        }
    }

    public int getCaretPosition() { return text != null ? text.length() : 0; }
    public void setInitialInputMode(String characterSubset) { }

    /** Show native Decade TextBox UI */
    public void showNative() {
        NativeBridge.setTextBoxText(text != null ? text : "");
        NativeBridge.formBegin(getTitle() != null ? getTitle() : "", 3); // 3 = textbox
        NativeBridge.formAddTextField("", text != null ? text : "", maxSize, constraints);
        ArrayList<Command> cmds = getCommands();
        for (int i = 0; i < cmds.size(); i++) {
            Command c = cmds.get(i);
            NativeBridge.formAddCommand(c.getLabel(), c.getCommandType(), c.getPriority(), i);
        }
        NativeBridge.formShow();
    }
}
