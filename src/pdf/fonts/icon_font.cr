module PDF
  module Fonts
    # Icon font support — provides a mapping from human-readable icon names
    # to Unicode codepoints for use with icon TTF fonts like FontAwesome.
    #
    # ## Usage
    #
    # ```
    # # Load any icon font TTF
    # fa = pdf.load_font("fonts/fa-solid-900.ttf")
    #
    # pdf.page do |page|
    #   page.font fa, size: 24
    #   # Render by codepoint
    #   page.text IconFont.char(:home), at: {72, 720}
    #   # Or use the icon helper
    #   page.icon(:home, at: {72, 720}, font: fa, size: 24)
    # end
    # ```
    module IconFont
      # FontAwesome 6 Free Solid — most common icons.
      # Maps icon name to Unicode codepoint.
      FONTAWESOME = {
        home:             0xF015,
        search:           0xF002,
        user:             0xF007,
        star:             0xF005,
        heart:            0xF004,
        check:            0xF00C,
        times:            0xF00D,
        close:            0xF00D,
        plus:             0xF067,
        minus:            0xF068,
        cog:              0xF013,
        gear:             0xF013,
        trash:            0xF1F8,
        edit:             0xF044,
        pencil:           0xF303,
        envelope:         0xF0E0,
        phone:            0xF095,
        lock:             0xF023,
        unlock:           0xF09C,
        eye:              0xF06E,
        eye_slash:        0xF070,
        download:         0xF019,
        upload:           0xF093,
        print:            0xF02F,
        save:             0xF0C7,
        file:             0xF15B,
        folder:           0xF07B,
        folder_open:      0xF07C,
        copy:             0xF0C5,
        paste:            0xF0EA,
        link:             0xF0C1,
        unlink:           0xF127,
        bold:             0xF032,
        italic:           0xF033,
        underline:        0xF0CD,
        list:             0xF03A,
        list_ol:          0xF0CB,
        list_ul:          0xF0CA,
        table:            0xF0CE,
        image:            0xF03E,
        camera:           0xF030,
        video:            0xF03D,
        music:            0xF001,
        play:             0xF04B,
        pause:            0xF04C,
        stop:             0xF04D,
        forward:          0xF04E,
        backward:         0xF04A,
        arrow_up:         0xF062,
        arrow_down:       0xF063,
        arrow_left:       0xF060,
        arrow_right:      0xF061,
        chevron_up:       0xF077,
        chevron_down:     0xF078,
        chevron_left:     0xF053,
        chevron_right:    0xF054,
        angle_up:         0xF106,
        angle_down:       0xF107,
        angle_left:       0xF104,
        angle_right:      0xF105,
        spinner:          0xF110,
        circle:           0xF111,
        square:           0xF0C8,
        exclamation:      0xF12A,
        question:         0xF128,
        info:             0xF129,
        info_circle:      0xF05A,
        warning:          0xF071,
        exclamation_triangle: 0xF071,
        ban:              0xF05E,
        bell:             0xF0F3,
        bookmark:         0xF02E,
        calendar:         0xF133,
        clock:            0xF017,
        comment:          0xF075,
        comments:         0xF086,
        compass:          0xF14E,
        credit_card:      0xF09D,
        database:         0xF1C0,
        desktop:          0xF108,
        mobile:           0xF3CD,
        tablet:           0xF3FA,
        globe:            0xF0AC,
        map:              0xF279,
        map_marker:       0xF3C5,
        location:         0xF3C5,
        shield:           0xF3ED,
        key:              0xF084,
        sign_in:          0xF2F6,
        sign_out:         0xF2F5,
        tag:              0xF02B,
        tags:             0xF02C,
        thumbs_up:        0xF164,
        thumbs_down:      0xF165,
        trophy:           0xF091,
        wrench:           0xF0AD,
        code:             0xF121,
        terminal:         0xF120,
        bug:              0xF188,
        fire:             0xF06D,
        flag:             0xF024,
        gift:             0xF06B,
        lightbulb:        0xF0EB,
        magic:            0xF0D0,
        rocket:           0xF135,
        sync:             0xF021,
        redo:             0xF01E,
        undo:             0xF0E2,
        bars:             0xF0C9,
        ellipsis_h:       0xF141,
        ellipsis_v:       0xF142,
        expand:           0xF065,
        compress:         0xF066,
        external_link:    0xF35D,
        share:            0xF064,
        wifi:             0xF1EB,
        battery_full:     0xF240,
        power_off:        0xF011,
      }

      # Returns the character for a named icon.
      #
      # ```
      # IconFont.char(:home)   # => "\uF015"
      # IconFont.char(:search) # => "\uF002"
      # ```
      def self.char(name : Symbol) : String
        codepoint = FONTAWESOME[name]? || raise ArgumentError.new("Unknown icon: #{name}. Available icons: #{FONTAWESOME.keys.join(", ")}")
        codepoint.chr.to_s
      end

      # Returns the Unicode codepoint for a named icon.
      def self.codepoint(name : Symbol) : Int32
        FONTAWESOME[name]? || raise ArgumentError.new("Unknown icon: #{name}")
      end

      # Returns all available icon names.
      def self.available_icons : Array(Symbol)
        FONTAWESOME.keys.to_a
      end

      # Checks if an icon name is available.
      def self.has_icon?(name : Symbol) : Bool
        FONTAWESOME.has_key?(name)
      end
    end
  end
end
