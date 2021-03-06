// This file is part of GNOME Boxes. License: LGPLv2+

private interface Boxes.IConfig {

    protected abstract KeyFile keyfile { get; }
    public abstract string? filename { get; set; }
    protected abstract bool has_file { get; set; }

    public void save () {
        keyfile_save (keyfile, get_pkgconfig_source (filename), has_file);
        has_file = true;
    }

    public bool get_boolean (string group, string key, bool default_value = false) {
        try {
            return keyfile.get_boolean (group, key);
        } catch (GLib.KeyFileError error) {
            return default_value;
        }
    }

    public void set_boolean (string group, string key, bool value) {
        keyfile.set_boolean (group, key, value);
    }

    protected void load () throws GLib.Error {
        if (!has_file)
            throw new Boxes.Error.INVALID ("has_file is false");

        keyfile.load_from_file (get_pkgconfig_source (filename),
                                KeyFileFlags.KEEP_COMMENTS | KeyFileFlags.KEEP_TRANSLATIONS);
    }

    protected string? get_string (string group, string key) {
        try {
            return keyfile.get_string (group, key);
        } catch (GLib.KeyFileError error) {
            return null;
        }
    }

    protected string[]? get_string_list (string group, string key) {
        try {
            return keyfile.get_string_list (group, key);
        } catch (GLib.KeyFileError error) {
            return null;
        }
    }
}

private class Boxes.CollectionSource: GLib.Object, Boxes.IConfig {
    private KeyFile _keyfile;
    private KeyFile keyfile { get { return _keyfile; } }

    private bool has_file { get; set; }

    private string? _filename;
    public string? filename {
        get {
            if (_filename == null)
                _filename = make_filename (name);
            return _filename;
        }
        set { _filename = value; }
    }

    public string? name {
        owned get { return get_string ("source", "name"); }
        set {
            keyfile.set_string ("source", "name", value);
            var had_file = has_file;
            this.delete ();
            _filename = null;
            if (had_file)
                save ();
        }
    }
    public string? source_type {
        owned get { return get_string ("source", "type"); }
        set { keyfile.set_string ("source", "type", value); }
    }
    public string? uri {
        owned get { return get_string ("source", "uri"); }
        set { keyfile.set_string ("source", "uri", value); }
    }
    public bool enabled {
        get { return get_boolean ("source", "enabled", true); }
        set { set_boolean ("source", "enabled", value); }
    }

    construct {
        _keyfile = new KeyFile ();
    }

    public CollectionSource (string name, string source_type, string uri) {
        this.name = name;
        this.source_type = source_type;
        this.uri = uri;
    }

    public CollectionSource.with_file (string filename) throws GLib.Error {
        this.filename = filename;
        has_file = true;
        load ();
    }

    public void delete () {
        if (!has_file)
            return;

        FileUtils.unlink (get_pkgconfig_source (filename));
        has_file = false;
    }
}
