{
  # this is necessary even with xkb and sway remapping, because it works a the device level and
  # Caplock won't be Control there unless we set it here.
  modmap = [
    {
      name = "Remap Capslock";
      remap = {
        CapsLock = "Control_L";
      };
    }
  ];
  keymap = [
    {
      name = "Emacs";
      application = {
        not = [
          "Emacs"
          "foot"
          "firefox"
        ];
      };
      remap = {
        # n=b
        C-n = {
          with_mark = "left";
        };
        # y=f
        C-y = {
          with_mark = "right";
        };
        # r=p
        C-r = {
          with_mark = "up";
        };
        # l=n
        C-l = {
          with_mark = "down";
        };
        # Forward/Backward word
        # n=b
        M-n = {
          with_mark = "C-left";
        };
        # y=f
        M-y = {
          with_mark = "C-right";
        };
        # Beginning/End of line
        C-a = {
          with_mark = "home";
        };
        # d=e
        C-d = {
          with_mark = "end";
        };
        # Page up/down
        # dot=v
        M-dot = {
          with_mark = "pageup";
        };
        C-dot = {
          with_mark = "pagedown";
        };
        # Beginning/End of file
        # w=comma
        M-Shift-w = {
          with_mark = "C-home";
        };
        # e=dot
        M-Shift-e = {
          with_mark = "C-end";
        };
        # Newline
        C-m = "enter";
        # c=j
        C-c = "enter";
        # s=o
        C-s = [
          "enter"
          "left"
        ];
        # Copy
        # comma=w
        C-comma = [
          # b=x
          "C-b"
          { set_mark = false; }
        ];
        # comma=w
        M-comma = [
          # i=c
          "C-i"
          { set_mark = false; }
        ];
        # t=y
        C-t = [
          # dot=v
          "C-dot"
          { set_mark = false; }
        ];
        # Delete
        # h=d
        C-h = [
          "delete"
          { set_mark = false; }
        ];
        M-h = [
          "C-delete"
          { set_mark = false; }
        ];
        # Kill line
        # v=k
        C-v = [
          "Shift-end"
          # b=x
          "C-b"
          { set_mark = false; }
        ];
        # Kill word backward
        Alt-backspace = [
          "C-backspace"
          { set_mark = false; }
        ];
        # set mark next word continuously.
        C-M-space = [
          "C-Shift-right"
          { set_mark = true; }
        ];
        # Undo
        # leftbrace=slash
        C-leftbrace = [
          # slash=z
          "C-slash"
          { set_mark = false; }
        ];
        # apostgrophe=hyphen
        C-Shift-apostrophe = [
          # slash=z
          "C-slash"
          { set_mark = false; }
        ];
        C-Shift-ro = [
          # slash=z
          "C-slash"
          { set_mark = false; }
        ];
        # Mark
        C-space = {
          set_mark = true;
        };
        # Search
        # semicolon=s
        # y=f
        C-semicolon = "C-y";
        # o=r
        C-o = "Shift-F3";
        # j=h
        M-Shift-5 = "C-j";
        # Cancel
        # u=g
        C-u = [
          "esc"
          { set_mark = false; }
        ];
        # C-x YYY
        # b=x
        C-b = {
          remap = {
            # C-x h (select all)
            # j=h
            j = [
              "C-home"
              "C-a"
              { set_mark = true; }
            ];
            # C-x C-f (open)
            # y=f
            # s=o
            C-y = "C-s";
            # C-x C-s (save)
            # semicolon=s
            C-semicolon = "C-semicolon";
            # C-x k (kill tab)
            # v=k
            v = "C-f4";
            # C-x C-c (exit)
            # i=c
            # x=q
            C-i = "C-x";
            # C-x u (undo)
            # f=u
            f = [
              # slash=z
              "C-slash"
              { set_mark = false; }
            ];
          };
        };
      };
    }
    {
      name = "Firefox";
      application = {
        only = "firefox";
      };
      remap = {
        # n=b
        C-n = {
          with_mark = "left";
        };
        # y=f
        C-y = {
          with_mark = "right";
        };
        # r=p
        C-r = {
          with_mark = "up";
        };
        # l=n
        C-l = {
          with_mark = "down";
        };
        # Forward/Backward word
        # n=b
        M-n = {
          with_mark = "C-left";
        };
        # y=f
        M-y = {
          with_mark = "C-right";
        };
        # Beginning/End of line
        C-a = {
          with_mark = "home";
        };
        # d=e
        C-d = {
          with_mark = "end";
        };
        # Page up/down
        # dot=v
        M-dot = {
          with_mark = "pageup";
        };
        C-dot = {
          with_mark = "pagedown";
        };
        # Beginning/End of file
        # w=comma
        M-Shift-w = {
          with_mark = "C-home";
        };
        # e=dot
        M-Shift-e = {
          with_mark = "C-end";
        };
        # Newline
        C-m = "enter";
        # c=j
        C-c = "enter";
        # s=o
        # C-s = [
        #   "enter"
        #   "left"
        # ];
        # Copy
        # comma=w
        C-comma = [
          # b=x
          "C-b"
          { set_mark = false; }
        ];
        # comma=w
        M-comma = [
          # i=c
          "C-i"
          { set_mark = false; }
        ];
        # t=y
        C-t = [
          # dot=v
          "C-dot"
          { set_mark = false; }
        ];
        # Delete
        # h=d
        C-h = [
          "delete"
          { set_mark = false; }
        ];
        M-h = [
          "C-delete"
          { set_mark = false; }
        ];
        # Kill line
        # v=k
        C-v = [
          "Shift-end"
          # b=x
          "C-b"
          { set_mark = false; }
        ];
        # Kill word backward
        Alt-backspace = [
          "C-backspace"
          { set_mark = false; }
        ];
        # set mark next word continuously.
        C-M-space = [
          "C-Shift-right"
          { set_mark = true; }
        ];
        # Undo
        # leftbrace=slash
        C-leftbrace = [
          # slash=z
          "C-slash"
          { set_mark = false; }
        ];
        # apostgrophe=hyphen
        C-Shift-apostrophe = [
          # slash=z
          "C-slash"
          { set_mark = false; }
        ];
        C-Shift-ro = [
          # slash=z
          "C-slash"
          { set_mark = false; }
        ];
        # Mark
        C-space = {
          set_mark = true;
        };
        # Search
        # semicolon=s
        # y=f
        C-semicolon = "C-y";
        # o=r
        # C-o = "Shift-F3";
        # j=h
        M-Shift-5 = "C-j";
        # Cancel
        # u=g
        C-u = [
          "esc"
          { set_mark = false; }
        ];
        # C-x YYY
        # b=x
        C-b = {
          remap = {
            # C-x h (select all)
            # j=h
            j = [
              "C-home"
              "C-a"
              { set_mark = true; }
            ];
            # C-x C-f (open)
            # y=f
            # s=o
            C-y = "C-s";
            # C-x C-s (save)
            # semicolon=s
            C-semicolon = "C-semicolon";
            # C-x k (kill tab)
            # v=k
            v = "C-f4";
            # C-x C-c (exit)
            # i=c
            # x=q
            C-i = "C-x";
            # C-x u (undo)
            # f=u
            f = [
              # slash=z
              "C-slash"
              { set_mark = false; }
            ];
          };
        };
      };
    }
  ];
}
