package javax.microedition.lcdui;

import java.util.ArrayList;

public class Form extends Screen {
    private ArrayList<Item> items = new ArrayList<Item>();
    private ItemStateListener itemStateListener;
    private boolean dispatchingNativeEdits;
    private boolean nativeUpdatePending;

    public Form(String title) {
        setTitle(title);
    }

    public Form(String title, Item[] itemArray) {
        setTitle(title);
        if (itemArray != null) {
            for (Item item : itemArray) append(item);
        }
    }

    public int append(Item item) {
        if (item == null) throw new NullPointerException();
        item.owner = this;
        items.add(item);
        requestNativeRefresh();
        return items.size() - 1;
    }

    public int append(String str) {
        return append(new StringItem(null, str));
    }

    public int append(Image img) {
        return append(new ImageItem(null, img, ImageItem.LAYOUT_DEFAULT, ""));
    }

    public void insert(int index, Item item) {
        item.owner = this;
        items.add(index, item);
        requestNativeRefresh();
    }

    public void set(int index, Item item) {
        item.owner = this;
        Item old = items.set(index, item);
        if (old != item && old.owner == this) old.owner = null;
        requestNativeRefresh();
    }

    public void delete(int index) {
        Item old = items.remove(index);
        if (old.owner == this) old.owner = null;
        requestNativeRefresh();
    }

    public void deleteAll() {
        for (Item item : items) {
            if (item.owner == this) item.owner = null;
        }
        items.clear();
        requestNativeRefresh();
    }
    public int size() { return items.size(); }
    public Item get(int index) { return items.get(index); }
    public void setItemStateListener(ItemStateListener listener) { itemStateListener = listener; }

    public void syncFromNative() {
        Item[] visibleItems = items.toArray(new Item[items.size()]);
        Item[] changedItems = new Item[visibleItems.length];
        int changedCount = 0;
        for (int i = 0; i < visibleItems.length; i++) {
            Item item = visibleItems[i];
            if (item instanceof TextField) {
                TextField field = (TextField) item;
                String value = NativeBridge.getFormItemText(i);
                if (value == null || (field.getConstraints() & TextField.UNEDITABLE) != 0) continue;
                if (field.applyValue(value)) changedItems[changedCount++] = field;
            } else if (item instanceof ChoiceGroup) {
                if (applyNativeChoice((ChoiceGroup) item, NativeBridge.getFormItemText(i))) {
                    changedItems[changedCount++] = item;
                }
            }
        }

        // Item listeners can repopulate the form and replace the native rows.
        // Deliver those callbacks only after every visible value has been copied.
        if (changedCount == 0 || itemStateListener == null) return;
        dispatchingNativeEdits = true;
        try {
            for (int i = 0; i < changedCount; i++) {
                if (items.contains(changedItems[i])) notifyItemStateChanged(changedItems[i]);
            }
        } finally {
            dispatchingNativeEdits = false;
            if (nativeUpdatePending) {
                nativeUpdatePending = false;
                requestNativeRefresh();
            }
        }
    }

    private boolean applyNativeChoice(ChoiceGroup choice, String value) {
        if (value == null) return false;
        int firstBreak = value.indexOf('\n');
        if (firstBreak < 0) return false;
        if (choice.choiceType != Choice.MULTIPLE) {
            try {
                int index = Integer.parseInt(value.substring(0, firstBreak).trim());
                if (index < 0 || index >= choice.size() || index == choice.getSelectedIndex()) return false;
                choice.setSelectedIndex(index, true);
                return true;
            } catch (NumberFormatException invalidIndex) {
                return false;
            }
        }

        int flagsStart = value.indexOf('\n', firstBreak + 1);
        if (flagsStart < 0) return false;
        String[] flags = value.substring(flagsStart + 1).split(",");
        if (flags.length != choice.size()) return false;
        boolean[] selected = new boolean[flags.length];
        boolean changed = false;
        for (int i = 0; i < flags.length; i++) {
            String flag = flags[i].trim();
            if (!"0".equals(flag) && !"1".equals(flag)) return false;
            selected[i] = "1".equals(flag);
            changed |= selected[i] != choice.isSelected(i);
        }
        if (changed) choice.setSelectedFlags(selected);
        return changed;
    }

    void notifyItemStateChanged(Item item) {
        if (itemStateListener != null) itemStateListener.itemStateChanged(item);
    }

    /** Serialize form to native bridge and show it. */
    public void showNative() {
        if (dispatchingNativeEdits) {
            nativeUpdatePending = true;
            return;
        }
        NativeBridge.formBegin(getTitle(), 0); // type 0 = form
        for (Item item : items) {
            int type = item.getItemType();
            if (type == 0) { // StringItem
                NativeBridge.formAddStringItem(item.getItemLabel(), item.getItemText(), 0);
            } else if (type == 1) { // TextField
                TextField tf = (TextField) item;
                NativeBridge.formAddTextField(item.getItemLabel(), item.getItemText(),
                        tf.getMaxSize(), tf.getConstraints());
            } else if (type == 2 && item instanceof ChoiceGroup) { // ChoiceGroup
                ChoiceGroup cg = (ChoiceGroup) item;
                StringBuilder sb = new StringBuilder();
                sb.append(cg.getSelectedIndex()).append("\n");
                for (int j = 0; j < cg.size(); j++) {
                    if (j > 0) sb.append("\t");
                    sb.append(cg.getString(j));
                }
                sb.append("\n");
                for (int j = 0; j < cg.size(); j++) {
                    if (j > 0) sb.append(",");
                    sb.append(cg.isSelected(j) ? "1" : "0");
                }
                try {
                    NativeBridge.formAddChoiceGroup(item.getItemLabel(), sb.toString(), cg.choiceType);
                } catch (Throwable t) {
                    NativeBridge.formAddTextField(item.getItemLabel(), sb.toString(), cg.choiceType, cg.choiceType);
                }
            } else {
                // Fallback: show as string
                NativeBridge.formAddStringItem(item.getItemLabel(), item.getItemText(), 0);
            }
        }
        // Commands
        ArrayList<Command> cmds = getCommands();
        for (int i = 0; i < cmds.size(); i++) {
            Command c = cmds.get(i);
            NativeBridge.formAddCommand(c.getLabel(), c.getCommandType(), c.getPriority(), i);
        }
        NativeBridge.formShow();
    }
}
