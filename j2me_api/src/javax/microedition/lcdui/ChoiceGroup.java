package javax.microedition.lcdui;

import java.util.ArrayList;

public class ChoiceGroup extends Item implements Choice {
    int choiceType;
    private ArrayList<String> strings = new ArrayList<String>();
    private ArrayList<Image> images = new ArrayList<Image>();
    private ArrayList<Boolean> selected = new ArrayList<Boolean>();

    public ChoiceGroup(String label, int choiceType) { setLabel(label); this.choiceType = choiceType; }
    public ChoiceGroup(String label, int choiceType, String[] stringElements, Image[] imageElements) {
        this(label, choiceType);
        if (stringElements != null) for (int i = 0; i < stringElements.length; i++)
            append(stringElements[i], imageElements != null && i < imageElements.length ? imageElements[i] : null);
    }

    public int append(String s, Image img) {
        boolean firstExclusive = (strings.isEmpty() && (choiceType == EXCLUSIVE || choiceType == POPUP));
        strings.add(s != null ? s : "");
        images.add(img);
        selected.add(firstExclusive ? Boolean.TRUE : Boolean.FALSE);
        return strings.size() - 1;
    }
    public void delete(int i) {
        if (i < 0 || i >= strings.size()) return;
        boolean wasSelected = selected.get(i);
        strings.remove(i);
        images.remove(i);
        selected.remove(i);
        if (wasSelected && !selected.isEmpty() && (choiceType == EXCLUSIVE || choiceType == POPUP)) {
            int nextIdx = Math.min(i, selected.size() - 1);
            selected.set(nextIdx, Boolean.TRUE);
        }
    }
    public void deleteAll() { strings.clear(); images.clear(); selected.clear(); }
    public int getSelectedIndex() {
        if (choiceType == MULTIPLE) return -1;
        for (int i = 0; i < selected.size(); i++) if (selected.get(i)) return i;
        return selected.isEmpty() ? -1 : 0;
    }
    public String getString(int i) { return strings.get(i); }
    public Image getImage(int i) { return images.get(i); }
    public void insert(int i, String s, Image img) {
        boolean firstExclusive = (strings.isEmpty() && (choiceType == EXCLUSIVE || choiceType == POPUP));
        strings.add(i, s != null ? s : "");
        images.add(i, img);
        selected.add(i, firstExclusive ? Boolean.TRUE : Boolean.FALSE);
    }
    public boolean isSelected(int i) { return i >= 0 && i < selected.size() && selected.get(i); }
    public void set(int i, String s, Image img) { strings.set(i, s != null ? s : ""); images.set(i, img); }
    public void setSelectedIndex(int i, boolean s) {
        if (i < 0 || i >= selected.size()) return;
        if (choiceType == EXCLUSIVE || choiceType == POPUP) {
            if (s) {
                for (int j = 0; j < selected.size(); j++) selected.set(j, Boolean.FALSE);
                selected.set(i, Boolean.TRUE);
            } else {
                selected.set(i, Boolean.FALSE);
            }
        } else {
            selected.set(i, s ? Boolean.TRUE : Boolean.FALSE);
        }
    }
    public int size() { return strings.size(); }
    public int getSelectedFlags(boolean[] a) {
        if (a == null) throw new NullPointerException();
        int count = 0;
        for (int i = 0; i < a.length; i++) {
            if (i < selected.size()) {
                boolean sel = selected.get(i);
                a[i] = sel;
                if (sel) count++;
            } else {
                a[i] = false;
            }
        }
        return count;
    }
    public void setSelectedFlags(boolean[] a) {
        if (a == null) throw new NullPointerException();
        if (choiceType == EXCLUSIVE || choiceType == POPUP) {
            int firstTrue = -1;
            for (int i = 0; i < selected.size() && i < a.length; i++) {
                if (a[i]) { firstTrue = i; break; }
            }
            if (firstTrue < 0 && !selected.isEmpty()) firstTrue = 0;
            for (int i = 0; i < selected.size(); i++) {
                selected.set(i, (i == firstTrue) ? Boolean.TRUE : Boolean.FALSE);
            }
        } else {
            for (int i = 0; i < a.length && i < selected.size(); i++) {
                selected.set(i, a[i] ? Boolean.TRUE : Boolean.FALSE);
            }
        }
    }
    public int getFitPolicy() { return 0; }
    public void setFitPolicy(int p) {}
    public Font getFont(int i) { return Font.getDefaultFont(); }
    public void setFont(int i, Font f) {}

    int getItemType() { return 2; }
    String getItemText() { return strings.size()>0?strings.get(getSelectedIndex()>=0?getSelectedIndex():0):""; }
}
