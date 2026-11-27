package javax.microedition.lcdui;

public class TextField extends Item {
    public static final int ANY = 0;
    public static final int EMAILADDR = 1;
    public static final int NUMERIC = 2;
    public static final int PHONENUMBER = 3;
    public static final int URL = 4;
    public static final int DECIMAL = 5;
    public static final int PASSWORD = 0x10000;
    public static final int UNEDITABLE = 0x20000;
    public static final int SENSITIVE = 0x40000;
    public static final int NON_PREDICTIVE = 0x80000;
    public static final int INITIAL_CAPS_WORD = 0x100000;
    public static final int INITIAL_CAPS_SENTENCE = 0x200000;
    public static final int CONSTRAINT_MASK = 0xFFFF;

    private String text;
    private int maxSize;
    private int constraints;

    public TextField(String label, String text, int maxSize, int constraints) {
        setLabel(label);
        this.text = text != null ? text : "";
        this.maxSize = maxSize;
        this.constraints = constraints;
    }

    public String getString() { return text; }
    public void setString(String text) {
        if (applyValue(text) && owner != null) owner.requestNativeRefresh();
    }

    boolean applyValue(String text) {
        String val = (text != null) ? text : "";
        if (maxSize > 0 && val.length() > maxSize) {
            val = val.substring(0, maxSize);
        }
        if (val.equals(this.text)) return false;
        this.text = val;
        return true;
    }
    public int getChars(char[] data) {
        if (data == null) throw new NullPointerException();
        int len = text.length();
        if (data.length < len) throw new ArrayIndexOutOfBoundsException();
        text.getChars(0, len, data, 0);
        return len;
    }
    public void setChars(char[] data, int offset, int length) {
        if (data == null) {
            setString("");
            return;
        }
        setString(new String(data, offset, length));
    }
    public int getMaxSize() { return maxSize; }
    public int setMaxSize(int maxSize) {
        if (maxSize <= 0) throw new IllegalArgumentException();
        this.maxSize = maxSize;
        if (this.text.length() > maxSize) {
            this.text = this.text.substring(0, maxSize);
        }
        return maxSize;
    }
    public int getConstraints() { return constraints; }
    public void setConstraints(int constraints) { this.constraints = constraints; }
    public int size() { return text.length(); }
    public void insert(String src, int position) {
        if (src == null) throw new NullPointerException();
        int pos = Math.max(0, Math.min(position, text.length()));
        setString(text.substring(0, pos) + src + text.substring(pos));
    }
    public void insert(char[] data, int offset, int length, int position) {
        if (data == null) throw new NullPointerException();
        insert(new String(data, offset, length), position);
    }
    public void delete(int offset, int length) {
        if (offset < 0 || length < 0 || offset + length > text.length()) {
            throw new StringIndexOutOfBoundsException();
        }
        this.text = text.substring(0, offset) + text.substring(offset + length);
    }
    public int getCaretPosition() { return text.length(); }
    public void setInitialInputMode(String characterSubset) { }

    int getItemType() { return 1; }
    String getItemText() { return text; }
}
