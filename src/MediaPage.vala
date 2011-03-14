/* Copyright 2010-2011 Yorba Foundation
 *
 * This software is licensed under the GNU LGPL (version 2.1 or later).
 * See the COPYING file in this distribution. 
 */

public class MediaSourceItem : CheckerboardItem {
    private static Gdk.Pixbuf basis_sprocket_pixbuf = null;
    private static Gdk.Pixbuf current_sprocket_pixbuf = null;

    private bool enable_sprockets = false;

    // preserve the same constructor arguments and semantics as CheckerboardItem so that we're
    // a drop-in replacement
    public MediaSourceItem(ThumbnailSource source, Dimensions initial_pixbuf_dim, string title,
        bool marked_up = false, Pango.Alignment alignment = Pango.Alignment.LEFT) {
        base(source, initial_pixbuf_dim, title, marked_up, alignment);
        if (basis_sprocket_pixbuf == null)
            basis_sprocket_pixbuf = Resources.load_icon("sprocket.png", 0);
    }

    protected override void paint_image(Cairo.Context ctx, Gdk.Pixbuf pixbuf,
        Gdk.Point origin) {
        Dimensions pixbuf_dim = Dimensions.for_pixbuf(pixbuf);
        // sprocket geometry calculation (and possible adjustment) has to occur before we call
        // base.paint_image( ) because the base-class method needs the correct trinket horizontal
        // offset
        
        if (!enable_sprockets) {
            set_horizontal_trinket_offset(0);
        } else {
            double reduction_factor = ((double) pixbuf_dim.major_axis()) /
                ((double) ThumbnailCache.Size.LARGEST);
            int reduced_size = (int) (reduction_factor * basis_sprocket_pixbuf.width);

            if (current_sprocket_pixbuf == null || reduced_size != current_sprocket_pixbuf.width) {
                current_sprocket_pixbuf = basis_sprocket_pixbuf.scale_simple(reduced_size,
                    reduced_size, Gdk.InterpType.HYPER);
            }

            set_horizontal_trinket_offset(current_sprocket_pixbuf.width);
        }
                
        base.paint_image(ctx, pixbuf, origin);

        if (enable_sprockets) {
            paint_sprockets(ctx, origin, pixbuf_dim);
        }
    }

    protected void paint_one_sprocket(Cairo.Context ctx, Gdk.Point origin) {
        ctx.save();
        Gdk.cairo_set_source_pixbuf(ctx, current_sprocket_pixbuf, origin.x, origin.y);
        ctx.paint();
        ctx.restore();
    }

    protected void paint_sprockets(Cairo.Context ctx, Gdk.Point item_origin,
        Dimensions item_dimensions) {
        int num_sprockets = item_dimensions.height / current_sprocket_pixbuf.height;

        Gdk.Point left_paint_location = item_origin;
        Gdk.Point right_paint_location = item_origin;
        right_paint_location.x += (item_dimensions.width - current_sprocket_pixbuf.width);
        for (int i = 0; i < num_sprockets; i++) {
            paint_one_sprocket(ctx, left_paint_location);
            paint_one_sprocket(ctx, right_paint_location);

            left_paint_location.y += current_sprocket_pixbuf.height;
            right_paint_location.y += current_sprocket_pixbuf.height;
        }

        int straggler_pixels = item_dimensions.height % current_sprocket_pixbuf.height;
        if (straggler_pixels > 0) {
            ctx.save();

            Gdk.cairo_set_source_pixbuf(ctx, current_sprocket_pixbuf, left_paint_location.x,
                left_paint_location.y);
            ctx.rectangle(left_paint_location.x, left_paint_location.y,
                current_sprocket_pixbuf.get_width(), straggler_pixels);
            ctx.fill();

            Gdk.cairo_set_source_pixbuf(ctx, current_sprocket_pixbuf, right_paint_location.x,
                right_paint_location.y);
            ctx.rectangle(right_paint_location.x, right_paint_location.y,
                current_sprocket_pixbuf.get_width(), straggler_pixels);
            ctx.fill();

            ctx.restore();
        }
    }
    
    public void set_enable_sprockets(bool enable_sprockets) {
        this.enable_sprockets = enable_sprockets;
    }
}

public abstract class MediaPage : CheckerboardPage {
    public const int SORT_ORDER_ASCENDING = 0;
    public const int SORT_ORDER_DESCENDING = 1;

    // steppings should divide evenly into (Thumbnail.MAX_SCALE - Thumbnail.MIN_SCALE)
    public const int MANUAL_STEPPING = 16;
    public const int SLIDER_STEPPING = 4;

    public enum SortBy {
        MIN = 1,
        TITLE = 1,
        EXPOSURE_DATE = 2,
        RATING = 3,
        MAX = 3
    }

    protected class ZoomSliderAssembly : Gtk.ToolItem {
        public static Gtk.Adjustment global_slider_adjustment = null;

        private Gtk.HScale slider;
        
        public signal void zoom_changed();

        public ZoomSliderAssembly() {
            Gtk.HBox zoom_group = new Gtk.HBox(false, 0);

            Gtk.Image zoom_out = new Gtk.Image.from_pixbuf(Resources.load_icon(
                Resources.ICON_ZOOM_OUT, Resources.ICON_ZOOM_SCALE));
            Gtk.EventBox zoom_out_box = new Gtk.EventBox();
            zoom_out_box.set_above_child(true);
            zoom_out_box.set_visible_window(false);
            zoom_out_box.add(zoom_out);
            zoom_out_box.button_press_event.connect(on_zoom_out_pressed);
            
            zoom_group.pack_start(zoom_out_box, false, false, 0);

            // triggers lazy init of the global slider adjustment if it hasn't already been init'd
            get_global_thumbnail_scale();

            slider = new Gtk.HScale(global_slider_adjustment);
            slider.value_changed.connect(on_slider_changed);
            slider.set_draw_value(false);
            slider.set_size_request(200, -1);
            slider.set_tooltip_text(_("Adjust the size of the thumbnails"));

            zoom_group.pack_start(slider, false, false, 0);

            Gtk.Image zoom_in = new Gtk.Image.from_pixbuf(Resources.load_icon(
                Resources.ICON_ZOOM_IN, Resources.ICON_ZOOM_SCALE));
            Gtk.EventBox zoom_in_box = new Gtk.EventBox();
            zoom_in_box.set_above_child(true);
            zoom_in_box.set_visible_window(false);
            zoom_in_box.add(zoom_in);
            zoom_in_box.button_press_event.connect(on_zoom_in_pressed);

            zoom_group.pack_start(zoom_in_box, false, false, 0);

            add(zoom_group);
        }
        
        public static double scale_to_slider(int value) {
            assert(value >= Thumbnail.MIN_SCALE);
            assert(value <= Thumbnail.MAX_SCALE);
            
            return (double) ((value - Thumbnail.MIN_SCALE) / SLIDER_STEPPING);
        }

        public static int slider_to_scale(double value) {
            int res = ((int) (value * SLIDER_STEPPING)) + Thumbnail.MIN_SCALE;

            assert(res >= Thumbnail.MIN_SCALE);
            assert(res <= Thumbnail.MAX_SCALE);
            
            return res;
        }

        private bool on_zoom_out_pressed(Gdk.EventButton event) {
            snap_to_min();
            return true;
        }
        
        private bool on_zoom_in_pressed(Gdk.EventButton event) {
            snap_to_max();
            return true;
        }
        
        private void on_slider_changed() {
            zoom_changed();
        }
        
        public void snap_to_min() {
            slider.set_value(scale_to_slider(Thumbnail.MIN_SCALE));
        }

        public void snap_to_max() {
            slider.set_value(scale_to_slider(Thumbnail.MAX_SCALE));
        }
        
        public void increase_step() {
            int new_scale = compute_zoom_scale_increase(get_scale());

            if (get_scale() == new_scale)
                return;

            slider.set_value(scale_to_slider(new_scale));
        }
        
        public void decrease_step() {
            int new_scale = compute_zoom_scale_decrease(get_scale());

            if (get_scale() == new_scale)
                return;
            
            slider.set_value(scale_to_slider(new_scale));
        }
        
        public int get_scale() {
            return slider_to_scale(slider.get_value());
        }
    }
    
    private ZoomSliderAssembly? connected_slider = null;
    private DragAndDropHandler dnd_handler = null;
    private MediaViewTracker tracker;
    
    public MediaPage(string page_name) {
        base (page_name);
        
        tracker = new MediaViewTracker(get_view());
        
        get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());
        get_view().items_altered.connect(on_media_altered);

        get_view().freeze_notifications();
        get_view().set_property(CheckerboardItem.PROP_SHOW_TITLES, 
            Config.get_instance().get_display_photo_titles());
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, 
            Config.get_instance().get_display_photo_tags());
        get_view().set_property(Thumbnail.PROP_SIZE, get_thumb_size());
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS,
            Config.get_instance().get_display_photo_ratings());
        get_view().thaw_notifications();

        // enable drag-and-drop export of media
        dnd_handler = new DragAndDropHandler(this);
    }
    
    private static void set_global_thumbnail_scale(int new_scale) {
        if (get_global_thumbnail_scale() == new_scale)
            return;

        ZoomSliderAssembly.global_slider_adjustment.set_value(
            ZoomSliderAssembly.scale_to_slider(new_scale));
    }
   
    private static int compute_zoom_scale_increase(int current_scale) {
        int new_scale = current_scale + MANUAL_STEPPING;
        return new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }
    
    private static int compute_zoom_scale_decrease(int current_scale) {
        int new_scale = current_scale - MANUAL_STEPPING;
        return new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
    }
    
    protected override void init_collect_ui_filenames(Gee.List<string> ui_filenames) {
        base.init_collect_ui_filenames(ui_filenames);
        
        ui_filenames.add("media.ui");
    }
    
    protected override Gtk.ActionEntry[] init_collect_action_entries() {
        Gtk.ActionEntry[] actions = base.init_collect_action_entries();
        
        Gtk.ActionEntry file = { "FileMenu", null, TRANSLATABLE, null, null, null };
        file.label = _("_File");
        actions += file;

        Gtk.ActionEntry export = { "Export", Gtk.STOCK_SAVE_AS, TRANSLATABLE, "<Ctrl><Shift>E",
            TRANSLATABLE, on_export };
        export.label = Resources.EXPORT_MENU;
        export.tooltip = Resources.EXPORT_TOOLTIP;
        export.tooltip = _("Export the selected items to disk");
        actions += export;
       
        Gtk.ActionEntry send_to = { "SendTo", "document-send", TRANSLATABLE, null, 
            TRANSLATABLE, on_send_to };
        send_to.label = Resources.SEND_TO_MENU;
        send_to.tooltip = Resources.SEND_TO_TOOLTIP;
        actions += send_to;
        
        Gtk.ActionEntry edit = { "EditMenu", null, TRANSLATABLE, null, null, null };
        edit.label = _("_Edit");
        actions += edit;
        
        Gtk.ActionEntry remove_from_library = { "RemoveFromLibrary", Gtk.STOCK_REMOVE, TRANSLATABLE,
            "<Shift>Delete", TRANSLATABLE, on_remove_from_library };
        remove_from_library.label = Resources.REMOVE_FROM_LIBRARY_MENU;
        remove_from_library.tooltip = Resources.REMOVE_FROM_LIBRARY_PLURAL_TOOLTIP;
        actions += remove_from_library;
        
        Gtk.ActionEntry move_to_trash = { "MoveToTrash", "user-trash-full", TRANSLATABLE, "Delete",
            TRANSLATABLE, on_move_to_trash };
        move_to_trash.label = Resources.MOVE_TO_TRASH_MENU;
        move_to_trash.tooltip = Resources.MOVE_TO_TRASH_PLURAL_TOOLTIP;
        actions += move_to_trash;
        
        Gtk.ActionEntry photos = { "PhotosMenu", null, TRANSLATABLE, null, null, null };
        photos.label = _("_Photos");
        actions += photos;

        Gtk.ActionEntry event = { "EventsMenu", null, TRANSLATABLE, null, null, null };
        event.label = _("Even_ts");
        actions += event;

        Gtk.ActionEntry tags = { "TagsMenu", null, TRANSLATABLE, null, null, null };
        tags.label = _("Ta_gs");
        actions += tags;

        Gtk.ActionEntry new_event = { "NewEvent", Gtk.STOCK_NEW, TRANSLATABLE, "<Ctrl>N",
            TRANSLATABLE, on_new_event };
        new_event.label = Resources.NEW_EVENT_MENU;
        new_event.tooltip = Resources.NEW_EVENT_TOOLTIP;
        actions += new_event;
        
        Gtk.ActionEntry add_tags = { "AddTags", null, TRANSLATABLE, "<Ctrl>T", TRANSLATABLE, 
            on_add_tags };
        add_tags.label = Resources.ADD_TAGS_MENU;
        add_tags.tooltip = Resources.ADD_TAGS_TOOLTIP;
        actions += add_tags;
        
        Gtk.ActionEntry modify_tags = { "ModifyTags", null, TRANSLATABLE, "<Ctrl>M", TRANSLATABLE, 
            on_modify_tags };
        modify_tags.label = Resources.MODIFY_TAGS_MENU;
        modify_tags.tooltip = Resources.MODIFY_TAGS_TOOLTIP;
        actions += modify_tags;

        Gtk.ActionEntry increase_size = { "IncreaseSize", Gtk.STOCK_ZOOM_IN, TRANSLATABLE,
            "<Ctrl>plus", TRANSLATABLE, on_increase_size };
        increase_size.label = _("Zoom _In");
        increase_size.tooltip = _("Increase the magnification of the thumbnails");
        actions += increase_size;

        Gtk.ActionEntry decrease_size = { "DecreaseSize", Gtk.STOCK_ZOOM_OUT, TRANSLATABLE,
            "<Ctrl>minus", TRANSLATABLE, on_decrease_size };
        decrease_size.label = _("Zoom _Out");
        decrease_size.tooltip = _("Decrease the magnification of the thumbnails");
        actions += decrease_size;
        
        Gtk.ActionEntry flag = { "Flag", null, TRANSLATABLE, "<Ctrl>G", TRANSLATABLE, on_flag_unflag };
        flag.label = Resources.FLAG_MENU;
        flag.tooltip = Resources.FLAG_TOOLTIP;
        actions += flag;
        
        Gtk.ActionEntry set_rating = { "Rate", null, TRANSLATABLE, null, null, null };
        set_rating.label = Resources.RATING_MENU;
        actions += set_rating;

        Gtk.ActionEntry increase_rating = { "IncreaseRating", null, TRANSLATABLE, 
            "greater", TRANSLATABLE, on_increase_rating };
        increase_rating.label = Resources.INCREASE_RATING_MENU;
        increase_rating.tooltip = Resources.INCREASE_RATING_TOOLTIP;
        actions += increase_rating;

        Gtk.ActionEntry decrease_rating = { "DecreaseRating", null, TRANSLATABLE, 
            "less", TRANSLATABLE, on_decrease_rating };
        decrease_rating.label = Resources.DECREASE_RATING_MENU;
        decrease_rating.tooltip = Resources.DECREASE_RATING_TOOLTIP;
        actions += decrease_rating;

        Gtk.ActionEntry rate_rejected = { "RateRejected", null, TRANSLATABLE, 
            "9", TRANSLATABLE, on_rate_rejected };
        rate_rejected.label = Resources.rating_menu(Rating.REJECTED);
        rate_rejected.tooltip = Resources.rating_tooltip(Rating.REJECTED);
        actions += rate_rejected;

        Gtk.ActionEntry rate_unrated = { "RateUnrated", null, TRANSLATABLE, 
            "0", TRANSLATABLE, on_rate_unrated };
        rate_unrated.label = Resources.rating_menu(Rating.UNRATED);
        rate_unrated.tooltip = Resources.rating_tooltip(Rating.UNRATED);
        actions += rate_unrated;

        Gtk.ActionEntry rate_one = { "RateOne", null, TRANSLATABLE, 
            "1", TRANSLATABLE, on_rate_one };
        rate_one.label = Resources.rating_menu(Rating.ONE);
        rate_one.tooltip = Resources.rating_tooltip(Rating.ONE);
        actions += rate_one;

        Gtk.ActionEntry rate_two = { "RateTwo", null, TRANSLATABLE, 
            "2", TRANSLATABLE, on_rate_two };
        rate_two.label = Resources.rating_menu(Rating.TWO);
        rate_two.tooltip = Resources.rating_tooltip(Rating.TWO);
        actions += rate_two;

        Gtk.ActionEntry rate_three = { "RateThree", null, TRANSLATABLE, 
            "3", TRANSLATABLE, on_rate_three };
        rate_three.label = Resources.rating_menu(Rating.THREE);
        rate_three.tooltip = Resources.rating_tooltip(Rating.THREE);
        actions += rate_three;

        Gtk.ActionEntry rate_four = { "RateFour", null, TRANSLATABLE, 
            "4", TRANSLATABLE, on_rate_four };
        rate_four.label = Resources.rating_menu(Rating.FOUR);
        rate_four.tooltip = Resources.rating_tooltip(Rating.FOUR);
        actions += rate_four;

        Gtk.ActionEntry rate_five = { "RateFive", null, TRANSLATABLE, 
            "5", TRANSLATABLE, on_rate_five };
        rate_five.label = Resources.rating_menu(Rating.FIVE);
        rate_five.tooltip = Resources.rating_tooltip(Rating.FIVE);
        actions += rate_five;

        Gtk.ActionEntry edit_title = { "EditTitle", null, TRANSLATABLE, "F2", TRANSLATABLE,
            on_edit_title };
        edit_title.label = Resources.EDIT_TITLE_MENU;
        edit_title.tooltip = Resources.EDIT_TITLE_TOOLTIP;
        actions += edit_title;

        Gtk.ActionEntry view = { "ViewMenu", null, TRANSLATABLE, null, null, null };
        view.label = _("_View");
        actions += view;

        Gtk.ActionEntry sort_photos = { "SortPhotos", null, TRANSLATABLE, null, null, null };
        sort_photos.label = _("Sort _Photos");
        actions += sort_photos;

        Gtk.ActionEntry filter_photos = { "FilterPhotos", null, TRANSLATABLE, null, null, null };
        filter_photos.label = Resources.FILTER_PHOTOS_MENU;
        actions += filter_photos;
        
        Gtk.ActionEntry help = { "HelpMenu", null, TRANSLATABLE, null, null, null };
        help.label = _("_Help");
        actions += help;

        Gtk.ActionEntry play = { "PlayVideo", Gtk.STOCK_MEDIA_PLAY, TRANSLATABLE, "<Ctrl>Y",
            TRANSLATABLE, on_play_video };
        play.label = _("_Play Video");
        play.tooltip = _("Open the selected videos in the system video player");
        actions += play;

        return actions;
    }
    
    protected override Gtk.ToggleActionEntry[] init_collect_toggle_action_entries() {
        Gtk.ToggleActionEntry[] toggle_actions = base.init_collect_toggle_action_entries();
        
        Gtk.ToggleActionEntry titles = { "ViewTitle", null, TRANSLATABLE, "<Ctrl><Shift>T",
            TRANSLATABLE, on_display_titles, Config.get_instance().get_display_photo_titles() };
        titles.label = _("_Titles");
        titles.tooltip = _("Display the title of each photo");
        toggle_actions += titles;
        
        Gtk.ToggleActionEntry ratings = { "ViewRatings", null, TRANSLATABLE, "<Ctrl><Shift>N",
            TRANSLATABLE, on_display_ratings, Config.get_instance().get_display_photo_ratings() };
        ratings.label = Resources.VIEW_RATINGS_MENU;
        ratings.tooltip = Resources.VIEW_RATINGS_TOOLTIP;
        toggle_actions += ratings;

        Gtk.ToggleActionEntry tags = { "ViewTags", null, TRANSLATABLE, "<Ctrl><Shift>G",
            TRANSLATABLE, on_display_tags, Config.get_instance().get_display_photo_tags() };
        tags.label = _("Ta_gs");
        tags.tooltip = _("Display each photo's tags");
        toggle_actions += tags;

        return toggle_actions;
    }
    
    protected override void register_radio_actions(Gtk.ActionGroup action_group) {
        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);
        
        Gtk.RadioActionEntry[] sort_crit_actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry by_title = { "SortByTitle", null, TRANSLATABLE, null, TRANSLATABLE,
            SortBy.TITLE };
        by_title.label = _("By _Title");
        by_title.tooltip = _("Sort photos by title");
        sort_crit_actions += by_title;
        
        Gtk.RadioActionEntry by_date = { "SortByExposureDate", null, TRANSLATABLE, null,
            TRANSLATABLE, SortBy.EXPOSURE_DATE };
        by_date.label = _("By Exposure _Date");
        by_date.tooltip = _("Sort photos by exposure date");
        sort_crit_actions += by_date;
        
        Gtk.RadioActionEntry by_rating = { "SortByRating", null, TRANSLATABLE, null,
            TRANSLATABLE, SortBy.RATING };
        by_rating.label = _("By _Rating");
        by_rating.tooltip = _("Sort photos by rating");
        sort_crit_actions += by_rating;
        
        action_group.add_radio_actions(sort_crit_actions, sort_by, on_sort_changed);
        
        Gtk.RadioActionEntry[] sort_order_actions = new Gtk.RadioActionEntry[0];
        
        Gtk.RadioActionEntry ascending = { "SortAscending", Gtk.STOCK_SORT_ASCENDING,
            TRANSLATABLE, null, TRANSLATABLE, SORT_ORDER_ASCENDING };
        ascending.label = _("_Ascending");
        ascending.tooltip = _("Sort photos in an ascending order");
        sort_order_actions += ascending;
        
        Gtk.RadioActionEntry descending = { "SortDescending", Gtk.STOCK_SORT_DESCENDING,
            TRANSLATABLE, null, TRANSLATABLE, SORT_ORDER_DESCENDING };
        descending.label = _("D_escending");
        descending.tooltip = _("Sort photos in a descending order");
        sort_order_actions += descending;
        
        action_group.add_radio_actions(sort_order_actions,
            sort_order ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING, on_sort_changed);
        
        base.register_radio_actions(action_group);
    }
    
    protected override void update_actions(int selected_count, int count) {
        set_action_sensitive("Export", selected_count > 0);
        set_action_sensitive("EditTitle", selected_count > 0);
        set_action_sensitive("IncreaseSize", get_thumb_size() < Thumbnail.MAX_SCALE);
        set_action_sensitive("DecreaseSize", get_thumb_size() > Thumbnail.MIN_SCALE);
        set_action_sensitive("RemoveFromLibrary", selected_count > 0);
        set_action_sensitive("MoveToTrash", selected_count > 0);
        
        if (DesktopIntegration.is_send_to_installed())
            set_action_sensitive("SendTo", selected_count > 0);
        else
            set_action_visible("SendTo", false);
        
        set_action_sensitive("Rate", selected_count > 0);
        update_rating_sensitivities();
        
        set_action_sensitive("PlayVideo", selected_count == 1
            && get_view().get_selected_source_at(0) is Video);
        
        update_flag_action(selected_count);
        
        base.update_actions(selected_count, count);
    }
    
    private void on_media_altered() {
        update_flag_action(get_view().get_selected_count());
    }
    
    private void update_rating_sensitivities() {
        set_action_sensitive("RateRejected", can_rate_selected(Rating.REJECTED));
        set_action_sensitive("RateUnrated", can_rate_selected(Rating.UNRATED));
        set_action_sensitive("RateOne", can_rate_selected(Rating.ONE));
        set_action_sensitive("RateTwo", can_rate_selected(Rating.TWO));
        set_action_sensitive("RateThree", can_rate_selected(Rating.THREE));
        set_action_sensitive("RateFour", can_rate_selected(Rating.FOUR));
        set_action_sensitive("RateFive", can_rate_selected(Rating.FIVE));
        set_action_sensitive("IncreaseRating", can_increase_selected_rating());
        set_action_sensitive("DecreaseRating", can_decrease_selected_rating());
    }
    
    private void update_flag_action(int selected_count) {
        set_action_sensitive("Flag", selected_count > 0);
        
        string flag_label = Resources.FLAG_MENU;
        string flag_tooltip = Resources.FLAG_TOOLTIP;
        if (selected_count > 0) {
            bool all_flagged = true;
            foreach (DataSource source in get_view().get_selected_sources()) {
                Flaggable? flaggable = source as Flaggable;
                if (flaggable != null && !flaggable.is_flagged()) {
                    all_flagged = false;
                    
                    break;
                }
            }
            
            if (all_flagged) {
                flag_label = Resources.UNFLAG_MENU;
                flag_tooltip = Resources.UNFLAG_TOOLTIP;
            }
        }
        
        Gtk.Action? flag_action = get_action("Flag");
        if (flag_action != null) {
            flag_action.label = flag_label;
            flag_action.tooltip = flag_tooltip;
        }
    }
    
    public override Core.ViewTracker? get_view_tracker() {
        return tracker;
    }
    
    public void set_display_ratings(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_RATINGS, display);
        get_view().thaw_notifications();
        
        Gtk.ToggleAction? action = get_action("ViewRatings") as Gtk.ToggleAction;
        if (action != null)
            action.set_active(display);
    }

    private bool can_rate_selected(Rating rating) {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_media_source().get_rating() != rating)
                return true;
        }

        return false;
    }

    private bool can_increase_selected_rating() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_media_source().get_rating().can_increase())
                return true;
        }

        return false;
    }

    private bool can_decrease_selected_rating() {
        foreach (DataView view in get_view().get_selected()) {
            if(((Thumbnail) view).get_media_source().get_rating().can_decrease())
                return true;
        }
        
        return false;
    }
    
    public ZoomSliderAssembly create_zoom_slider_assembly() {
        return new ZoomSliderAssembly();
    }
    
    public static int get_global_thumbnail_scale() {
        if (ZoomSliderAssembly.global_slider_adjustment == null) {
            int persisted_scale = Config.get_instance().get_photo_thumbnail_scale();
            ZoomSliderAssembly.global_slider_adjustment = new Gtk.Adjustment(
                ZoomSliderAssembly.scale_to_slider(persisted_scale), 0,
                ZoomSliderAssembly.scale_to_slider(Thumbnail.MAX_SCALE), 1, 10, 0);
        }

        return ZoomSliderAssembly.slider_to_scale(ZoomSliderAssembly.global_slider_adjustment.get_value());
    }

    protected override bool on_mousewheel_up(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            increase_zoom_level();
            return true;
        } else {
            return base.on_mousewheel_up(event);
        }
    }

    protected override bool on_mousewheel_down(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            decrease_zoom_level();
            return true;
        } else {
            return base.on_mousewheel_down(event);
        }
    }
    
    private void on_send_to() {
        DesktopIntegration.send_to((Gee.Collection<MediaSource>) get_view().get_selected_sources());
    }
    
    protected void on_play_video() {
        if (get_view().get_selected_count() != 1)
            return;
        
        Video? video = get_view().get_selected_at(0).get_source() as Video;
        if (video == null)
            return;
        
        try {
            AppInfo.launch_default_for_uri(video.get_file().get_uri(), null);
        } catch (Error e) {
            AppWindow.error_message(_("Shotwell was unable to play the selected video:\n%s").printf(
                e.message));
        }
    }

    protected override bool on_app_key_pressed(Gdk.EventKey event) {
        bool handled = true;
        switch (Gdk.keyval_name(event.keyval)) {
            case "equal":
            case "plus":
            case "KP_Add":
                activate_action("IncreaseSize");
            break;
            
            case "minus":
            case "underscore":
            case "KP_Subtract":
                activate_action("DecreaseSize");
            break;
            
            case "period":
                activate_action("IncreaseRating");
            break;
            
            case "comma":
                activate_action("DecreaseRating");
            break;
            
            case "KP_1":
                activate_action("RateOne");
            break;
            
            case "KP_2":
                activate_action("RateTwo");
            break;
            
            case "KP_3":
                activate_action("RateThree");
            break;
            
            case "KP_4":
                activate_action("RateFour");
            break;
            
            case "KP_5":
                activate_action("RateFive");
            break;
            
            case "KP_0":
                activate_action("RateUnrated");
            break;
            
            case "KP_9":
                activate_action("RateRejected");
            break;
            
            case "exclam":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.ONE_OR_HIGHER);
            break;
            
            case "at":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.TWO_OR_HIGHER);
            break;

            case "numbersign":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.THREE_OR_HIGHER);
            break;

            case "dollar":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.FOUR_OR_HIGHER);
            break;

            case "percent":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.FIVE_OR_HIGHER);
            break;

            case "parenright":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.UNRATED_OR_HIGHER);
            break;

            case "parenleft":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.REJECTED_OR_HIGHER);
            break;
            
            case "asterisk":
                if (get_ctrl_pressed())
                    get_search_view_filter().set_rating_filter(RatingFilter.REJECTED_ONLY);
            break;
            
            case "slash":
                activate_action("Flag");
            break;
            
            default:
                handled = false;
            break;
        }
        
        return handled ? true : base.on_app_key_pressed(event);
    }

    public override void switched_to() {
        base.switched_to();
        
        // the global thumbnail scale could've changed while another page was displayed, so
        // make sure that this page's thumb size matches the global thumbnail scale
        if (get_global_thumbnail_scale() != get_thumb_size())
            set_thumb_size(get_global_thumbnail_scale());

        // set display options to match Configuration toggles (which can change while switched away)
        get_view().freeze_notifications();
        set_display_titles(Config.get_instance().get_display_photo_titles());
        set_display_ratings(Config.get_instance().get_display_photo_ratings());
        set_display_tags(Config.get_instance().get_display_photo_tags());
        get_view().thaw_notifications();

        sync_sort();
    }

    protected void connect_slider(ZoomSliderAssembly slider) {
        connected_slider = slider;
        connected_slider.zoom_changed.connect(on_zoom_changed);
    }
    
    protected void disconnect_slider() {
        if (connected_slider == null)
            return;
        
        connected_slider.zoom_changed.disconnect(on_zoom_changed);
        connected_slider = null;
    }

    protected virtual void on_zoom_changed() {
        if (connected_slider != null)
            set_thumb_size(connected_slider.get_scale());
    }
    
    protected abstract void on_export();

    protected virtual void on_increase_size() {
        increase_zoom_level();
    }

    protected virtual void on_decrease_size() {
        decrease_zoom_level();
    }

    private void on_add_tags() {
        if (get_view().get_selected_count() == 0)
            return;
        
        AddTagsDialog dialog = new AddTagsDialog();
        string[]? names = dialog.execute();
        if (names != null) {
            get_command_manager().execute(new AddTagsCommand(names, 
                (Gee.Collection<MediaSource>) get_view().get_selected_sources()));
        }
    }

    private void on_modify_tags() {
        if (get_view().get_selected_count() != 1)
            return;
        
        MediaSource media = (MediaSource) get_view().get_selected_at(0).get_source();
        
        ModifyTagsDialog dialog = new ModifyTagsDialog(media);
        Gee.ArrayList<Tag>? new_tags = dialog.execute();
        
        if (new_tags == null)
            return;
        
        get_command_manager().execute(new ModifyTagsCommand(media, new_tags));
    }

    private void set_display_tags(bool display) {
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SHOW_TAGS, display);
        get_view().thaw_notifications();
        
        Gtk.ToggleAction? action = get_action("ViewTags") as Gtk.ToggleAction;
        if (action != null)
            action.set_active(display);
    }

    private void on_new_event() {
        if (get_view().get_selected_count() > 0)
            get_command_manager().execute(new NewEventCommand(get_view().get_selected()));
    }
    
    private void on_flag_unflag() {
        if (get_view().get_selected_count() == 0)
            return;
        
        Gee.Collection<DataSource> sources = get_view().get_selected_sources();
        
        // If all are flagged, then unflag, otherwise flag
        bool flag = false;
        foreach (DataSource source in sources) {
            Flaggable? flaggable = source as Flaggable;
            if (flaggable != null && !flaggable.is_flagged()) {
                flag = true;
                
                break;
            }
        }
        
        get_command_manager().execute(new FlagUnflagCommand(sources, flag));
    }
    
    protected virtual void on_increase_rating() {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand.inc_dec(get_view().get_selected(), true);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    protected virtual void on_decrease_rating() {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand.inc_dec(get_view().get_selected(), false);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    protected virtual void on_set_rating(Rating rating) {
        if (get_view().get_selected_count() == 0)
            return;
        
        SetRatingCommand command = new SetRatingCommand(get_view().get_selected(), rating);
        get_command_manager().execute(command);

        update_rating_sensitivities();
    }

    protected virtual void on_rate_rejected() {
        on_set_rating(Rating.REJECTED);
    }
    
    protected virtual void on_rate_unrated() {
        on_set_rating(Rating.UNRATED);
    }

    protected virtual void on_rate_one() {
        on_set_rating(Rating.ONE);
    }

    protected virtual void on_rate_two() {
        on_set_rating(Rating.TWO);
    }

    protected virtual void on_rate_three() {
        on_set_rating(Rating.THREE);
    }

    protected virtual void on_rate_four() {
        on_set_rating(Rating.FOUR);
    }

    protected virtual void on_rate_five() {
        on_set_rating(Rating.FIVE);
    }

    private void on_remove_from_library() {
        remove_photos_from_library((Gee.Collection<LibraryPhoto>) get_view().get_selected_sources());
    }
    
    protected virtual void on_move_to_trash() {
        if (get_view().get_selected_count() > 0) {
            get_command_manager().execute(new TrashUntrashPhotosCommand(
                (Gee.Collection<MediaSource>) get_view().get_selected_sources(), true));
        }
    }

    protected virtual void on_edit_title() {
        if (get_view().get_selected_count() == 0)
            return;
        
        Gee.List<MediaSource> media_sources = (Gee.List<MediaSource>) get_view().get_selected_sources();
        
        EditTitleDialog edit_title_dialog = new EditTitleDialog(media_sources[0].get_title());
        string? new_title = edit_title_dialog.execute();
        if (new_title != null)
            get_command_manager().execute(new EditMultipleTitlesCommand(media_sources, new_title));
    }

    protected virtual void on_display_titles(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_titles(display);
        
        Config.get_instance().set_display_photo_titles(display);
    }

    protected virtual void on_display_ratings(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_ratings(display);
        
        Config.get_instance().set_display_photo_ratings(display);
    }

    protected virtual void on_display_tags(Gtk.Action action) {
        bool display = ((Gtk.ToggleAction) action).get_active();
        
        set_display_tags(display);
        
        Config.get_instance().set_display_photo_tags(display);
    }

    protected abstract void get_config_photos_sort(out bool sort_order, out int sort_by);

    protected abstract void set_config_photos_sort(bool sort_order, int sort_by);

    protected virtual void on_sort_changed() {
        get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());

        set_config_photos_sort(get_sort_order() == SORT_ORDER_ASCENDING, get_sort_criteria());
    }

    protected override void set_display_titles(bool display) {
        base.set_display_titles(display);
    
        Gtk.ToggleAction? action = get_action("ViewTitle") as Gtk.ToggleAction;
        if (action != null)
            action.set_active(display);
    }

    protected int get_sort_criteria() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/MenuBar/ViewMenu/SortPhotos/SortByTitle");
        assert(action != null);
        
        int value = action.get_current_value();

        return value;
    }
    
    protected int get_sort_order() {
        // any member of the group knows the current value
        Gtk.RadioAction action = (Gtk.RadioAction) ui.get_action(
            "/MenuBar/ViewMenu/SortPhotos/SortAscending");
        assert(action != null);
        
        int value = action.get_current_value();
        
        return value;
    }
    
    protected bool is_sort_ascending() {
        return get_sort_order() == SORT_ORDER_ASCENDING;
    }
       
    protected Comparator get_sort_comparator() {
        switch (get_sort_criteria()) {
            case SortBy.TITLE:
                if (is_sort_ascending())
                    return Thumbnail.title_ascending_comparator;
                else
                    return Thumbnail.title_descending_comparator;
            
            case SortBy.EXPOSURE_DATE:
                if (is_sort_ascending())
                    return Thumbnail.exposure_time_ascending_comparator;
                else
                    return Thumbnail.exposure_time_desending_comparator;
            
            case SortBy.RATING:
                if (is_sort_ascending())
                    return Thumbnail.rating_ascending_comparator;
                else
                    return Thumbnail.rating_descending_comparator;
            
            default:
                error("Unknown sort criteria: %s", get_sort_criteria().to_string());
        }
    }
    
    protected ComparatorPredicate get_sort_comparator_predicate() {
        switch (get_sort_criteria()) {
            case SortBy.TITLE:
                return Thumbnail.title_comparator_predicate;
            
            case SortBy.EXPOSURE_DATE:
                return Thumbnail.exposure_time_comparator_predicate;
            
            case SortBy.RATING:
                return Thumbnail.rating_comparator_predicate;
            
            default:
                error("Unknown sort criteria: %s", get_sort_criteria().to_string());
        }
    }
          
    protected string get_sortby_path(int sort_by) {
        switch(sort_by) {
            case SortBy.TITLE:
                return "/MenuBar/ViewMenu/SortPhotos/SortByTitle";
            
            case SortBy.EXPOSURE_DATE:
                return "/MenuBar/ViewMenu/SortPhotos/SortByExposureDate";
            
            case SortBy.RATING:
                return "/MenuBar/ViewMenu/SortPhotos/SortByRating";
            
            default:
                error("Unknown sort criteria: %d", sort_by);
        }
    }

    protected void sync_sort() {
        bool sort_order;
        int sort_by;
        get_config_photos_sort(out sort_order, out sort_by);

        string path = get_sortby_path(sort_by);

        bool resort_needed = false;

        Gtk.RadioAction sort_by_action = (Gtk.RadioAction) ui.get_action(path);
        if (sort_by_action != null && sort_by_action.get_current_value() != sort_by) {
            sort_by_action.set_current_value(sort_by);
            resort_needed = true;
        }

        Gtk.RadioAction ascending_action = 
            (Gtk.RadioAction) ui.get_action("/MenuBar/ViewMenu/SortPhotos/SortAscending");

        int sort_order_int = sort_order ? SORT_ORDER_ASCENDING : SORT_ORDER_DESCENDING;
        if (ascending_action != null && ascending_action.get_current_value() != sort_order_int) {
            ascending_action.set_current_value(sort_order_int);
            resort_needed = true;
        }

        if (resort_needed)
            get_view().set_comparator(get_sort_comparator(), get_sort_comparator_predicate());
    }

    public override void destroy() {
        disconnect_slider();
        
        base.destroy();
    }

    public void increase_zoom_level() {
        if (connected_slider != null) {
            connected_slider.increase_step();
        } else {
            int new_scale = compute_zoom_scale_increase(get_thumb_size());
            set_global_thumbnail_scale(new_scale);
            set_thumb_size(new_scale);
        }
    }

    public void decrease_zoom_level() {
        if (connected_slider != null) {
            connected_slider.decrease_step();
        } else {
            int new_scale = compute_zoom_scale_decrease(get_thumb_size());
            set_global_thumbnail_scale(new_scale);
            set_thumb_size(new_scale);
        }
    }

    public virtual DataView create_thumbnail(DataSource source) {
        return new Thumbnail((MediaSource) source, get_thumb_size());
    }

    // this is a view-level operation on this page only; it does not affect the persistent global
    // thumbnail scale
    public void set_thumb_size(int new_scale) {
        if (get_thumb_size() == new_scale || !is_in_view())
            return;
        
        new_scale = new_scale.clamp(Thumbnail.MIN_SCALE, Thumbnail.MAX_SCALE);
        get_checkerboard_layout().set_scale(new_scale);
        
        // when doing mass operations on LayoutItems, freeze individual notifications
        get_view().freeze_notifications();
        get_view().set_property(Thumbnail.PROP_SIZE, new_scale);
        get_view().thaw_notifications();
        
        set_action_sensitive("IncreaseSize", new_scale < Thumbnail.MAX_SCALE);
        set_action_sensitive("DecreaseSize", new_scale > Thumbnail.MIN_SCALE);
    }

    public int get_thumb_size() {
        if (get_checkerboard_layout().get_scale() <= 0)
            get_checkerboard_layout().set_scale(Config.get_instance().get_photo_thumbnail_scale());
            
        return get_checkerboard_layout().get_scale();
    }
}

