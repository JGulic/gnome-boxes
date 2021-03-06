// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.SidebarPage {
    COLLECTION,
    WIZARD,
    PROPERTIES,
}

private class Boxes.Sidebar: Boxes.UI {
    public override Clutter.Actor actor { get { return gtk_actor; } }
    public Notebook notebook;
    public TreeView default_tree_view;
    public TreeView user_tree_view;
    public Category category;

    private App app;
    private uint width;

    private GtkClutter.Actor gtk_actor; // the sidebar box

    private bool selection_func (Gtk.TreeSelection selection,
                                 Gtk.TreeModel     model,
                                 Gtk.TreePath      path,
                                 bool              path_currently_selected) {
        Gtk.TreeIter iter;
        bool selectable;

        model.get_iter (out iter, path);
        model.get (iter, 2, out selectable);

        return selectable;
    }

    public Sidebar (App app) {
        this.app = app;
        width = 200;

        setup_sidebar ();
    }

    public override void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            notebook.page = SidebarPage.COLLECTION;
            break;

        case UIState.DISPLAY:
            actor_pin (actor);
            break;

        case UIState.WIZARD:
        case UIState.PROPERTIES:
            notebook.page = ui_state == UIState.WIZARD ? SidebarPage.WIZARD : SidebarPage.PROPERTIES;
            break;
        }
    }

    private void list_append (Gtk.ListStore listmodel,
                              Category  category,
                              string?   icon = null,
                              uint      height = 0,
                              bool      sensitive = true) {
        Gtk.TreeIter iter;

        listmodel.append (out iter);
        listmodel.set (iter, 0, category.name);
        listmodel.set (iter, 1, height);
        listmodel.set (iter, 2, sensitive);
        listmodel.set (iter, 3, icon);
        listmodel.set (iter, 4, category);
    }

    private Gtk.TreeView make_tree_view () {
        var tree_view = new Gtk.TreeView ();
        var selection = tree_view.get_selection ();
        selection.set_mode (Gtk.SelectionMode.BROWSE);
        selection.set_select_function (selection_func);
        tree_view_activate_on_single_click (tree_view, true);
        tree_view.row_activated.connect ( (treeview, path, column) => {
            Gtk.TreeIter iter;
            Category category;
            var model = treeview.get_model ();
            bool selectable;

            model.get_iter (out iter, path);
            model.get (iter, 4, out category);
            model.get (iter, 2, out selectable);

            if (selectable) {
                this.category = category;
                app.set_category (category);
            }

            (treeview == default_tree_view ? user_tree_view : default_tree_view).get_selection ().unselect_all ();
        });

        var listmodel = new ListStore (5,
                                       typeof (string),
                                       typeof (uint),
                                       typeof (bool),
                                       typeof (string),
                                       typeof (Category));
        tree_view.set_model (listmodel);
        tree_view.headers_visible = false;

        var pixbuf_renderer = new CellRendererPixbuf ();
        pixbuf_renderer.xpad = 5;
        tree_view.insert_column_with_attributes (-1, "", pixbuf_renderer, "icon-name", 3);
        var renderer = new CellRendererText ();
        tree_view.insert_column_with_attributes (-1, "", renderer, "text", 0, "height", 1, "sensitive", 2);

        return tree_view;
    }

    private void update_user_tree () {
        var listmodel = user_tree_view.get_model () as Gtk.ListStore;

        listmodel.clear ();
        foreach (var collection in app.settings.get_strv ("collections"))
            list_append (listmodel, new Category (_(collection)));
    }

    private void setup_sidebar () {
        notebook = new Gtk.Notebook ();
        gtk_actor = new GtkClutter.Actor.with_contents (notebook);
        notebook.get_style_context ().add_class ("boxes-sidebar-bg");
        notebook.set_size_request ((int) width, 100);
        notebook.show_tabs = false;

        /* SidebarPage.COLLECTION */
        var vbox = new Gtk.VBox (false, 0);
        notebook.append_page (vbox, null);

        default_tree_view = make_tree_view ();
        vbox.pack_start (default_tree_view, false, false, 0);

        var listmodel = default_tree_view.get_model () as Gtk.ListStore;
        category = new Category (_("New and Recent"), Category.Kind.NEW);
        list_append (listmodel, category);
        list_append (listmodel, new Category (_("Favorites"), Category.Kind.FAVORITES), "emblem-favorite-symbolic");
        list_append (listmodel, new Category (_("Private"), Category.Kind.PRIVATE), "channel-secure-symbolic");
        list_append (listmodel, new Category (_("Shared with you"), Category.Kind.SHARED), "emblem-shared-symbolic");
        default_tree_view.get_selection ().select_path (new Gtk.TreePath.from_string ("0"));

        var label = new Gtk.Label (_("Collections"));
        label.name = "CollectionLabel";
        label.xalign = 0.0f;
        label.margin = 10;
        label.margin_top = 20;
        var labelw = new Gtk.EventBox ();
        labelw.visible_window = true;
        labelw.add (label);
        vbox.pack_start (labelw, false, false, 0);

        user_tree_view = make_tree_view ();
        vbox.pack_start (user_tree_view, true, true, 0);
        update_user_tree ();

        var create = new Gtk.Button.with_label (_("Create"));
        create.margin = 5;
        vbox.pack_end (create, false, false, 0);
        create.show ();
        create.clicked.connect (() => {
            app.ui_state = UIState.WIZARD;
        });

        /* SidebarPage.WIZARD */
        vbox = new Gtk.VBox (false, 0);
        vbox.margin_top = 20;
        notebook.append_page (vbox, null);

        /* SidebarPage.PROPERTIES */
        vbox = new Gtk.VBox (false, 10);
        notebook.append_page (vbox, null);

        notebook.show_all ();

        // FIXME: make it dynamic depending on sidebar size..:
        app.state.set_key (null, "display", gtk_actor, "x", AnimationMode.EASE_OUT_QUAD, -(float) width, 0, 0);
    }
}
