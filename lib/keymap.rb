

$kmap = nil
def update_keymap(dpy)
  reply = dpy.get_keyboard_mapping


  if reply
    $kmap = reply.keysyms.map do |c|
      if c == 0
        nil
      elsif X11::KeySyms[c]
        X11::KeySyms[c]
      elsif c < 0x100
        c.chr(Encoding::ISO_8859_1)
      elsif c.between?(0xffb0, 0xffb9)
        "KP_#{c-0xffb0}".to_sym
      elsif c.between?(0xffbe, 0xffe0)
        "f#{c-0xffbe+1}".to_sym
      elsif c.between?(0xff08, 0xffff)
        # FIXME:
        raise "keyboard_#{c.to_s(16)}".to_s
      elsif c.between?(0x01000100, 0x0110FFFF)
        (c-0x01000100).
        chr(Encoding::UTF_32) rescue c.to_s(16)
      else
        STDERR.puts "keymap: unknown_#{c.to_s(16)}"
      end
    end.each_slice(reply.keysyms_per_keycode).to_a
    #ks = ks.map {|s| s.compact.sort_by{|x| x.to_s}.uniq }.to_a # This is for testing/ease of reading only
    p $kmap[47-dpy.display_info.min_keycode]
  end
end

def lookup_keysym(dpy,  event)
  update_keymap(dpy) if !$kmap
  $kmap[event.detail-dpy.display_info.min_keycode] rescue nil
end

SPECIALS = {
  "+" => :"ctrl_+",
  "-" => :"ctrl_-"
}

def lookup_string(dpy, event)
  ks = Array(lookup_keysym(dpy, event))
  str = ""
  shift = event.state.anybits?(0x01)
  meta  = event.state.anybits?(0x08)
  ctrl  = event.state.anybits?(0x04)
  i = shift && ks[1] ? 1 : 0

  return SPECIALS[ks[i]] if ctrl && SPECIALS[ks[i]]

  if shift
    case ks[i]
      # FIXME: This is messed up.
    when :XK_ISO_Left_Tab then return :shift_tab, nil
    when :XK_Down; then return :shift_down, nil
    when :XK_Up; then return :shift_up, nil
    end
  end
  
  if ks[i].is_a?(String)
    if ctrl
      str = (ks[i][0].ord & 0x9f).chr # Strip 0x60
    elsif meta
      str = "\e#{ks[i]}"
    else
      str = ks[i]
    end
  end
  p [ks[i], str]
  return ks[i], str
end



# Map X key events to escapes
KEYMAP = {
  :enter => "\r",
  :backspace => "\x7F",
  :tab => "\t",
  :f1 => "\e[11~",
  :f2 => "\e[12~",
  :f3 => "\e[13~",
  :f4 => "\e[14~",
  :f5 => "\e[15~",
  :f6 => "\e[16~",
  :f7 => "\e[17~",
  :f8 => "\e[18~",
  :f9 => "\e[19~",
  :f10 => "\e[20~",
  :f11 => "\e[21~",
  :f12 => "\e[22~",
  :shift_up => "\e[1;2A",
  :shift_down => "\e[1;2B",
  :shift_tab => "\e[Z",
  :XK_Left => "\e[D",
  :XK_Right => "\e[C",
  :XK_Down => "\e[B",
  :XK_ISO_Left_Tab => "\t",
  :XK_Up => "\e[A",
  :XK_Delete => "\e[P",
  :XK_Page_Up => "\x1b[5~",
  :XK_Page_Down => "\x1b[6~",
}

def keysym_to_vt102(ks)
  KEYMAP[ks]
end
