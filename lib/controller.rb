#
#  A spawned command that is controlling the terminal window,
#  and on request receives events (mouse buttons etc.
#
class Controller
  def initialize(term, config = {})
    @term = term
    @config = config
    @shell = determine_shell
  end

  def determine_shell
    # Try config file first, then ENV["SHELL"], then fallback to /bin/sh
    @config[:shell] || ENV["SHELL"] || "/bin/sh"
  end

  def run(*args)
    cmd = args.empty? ? @shell : [@shell, '-c', args.join(' ')]
    @master, @wr, @pid = *spawn_child(cmd)

    Thread.new do
      loop do
        begin
          @term.write(self.read)
          Thread.pass
        rescue Errno::EIO
          # The child closed the pty (it exited): EIO on read is normal
          # here. Exit with the child's status.
          # FIXME: Not sure if this really belongs *here*?
          exit(Process.wait(@pid))
        end
      end
    end
  end

  # Spawn the child shell/command with the user's own gem environment, not
  # rubyterm's bundle: when rubyterm runs under `bundle exec`, BUNDLE_GEMFILE /
  # GEM_PATH leak into children, so a Bundler-based shell (or any tool relying
  # on the system gems) fails to load its gems and exits immediately. Stripping
  # the bundle env restores the pre-bundle-exec behaviour.
  def spawn_child(cmd)
    if defined?(Bundler)
      Bundler.with_unbundled_env { PTY.spawn(*cmd) }
    else
      PTY.spawn(*cmd)
    end
  end

  def read
    @master.read_nonblock(128)
  rescue IO::EAGAINWaitReadable
    IO.select([@master], [], [], nil)
    retry
  end

  # Device Attributes replies. Each query has a distinct reply *type*;
  # sending the wrong type (e.g. the DA3 DCS below in answer to a DA1/DA2
  # query) makes hosts like tmux fail to consume it, so it leaks into the
  # pane as visible text.
  #
  # DA1 (CSI c): identify as a VT100 with Advanced Video Option.
  def device_attr_primary   = @wr.write("\e[?1;2c")
  # DA2 (CSI > c): terminal id 0 (VT100), firmware version, cartridge 0.
  def device_attr_secondary = @wr.write("\e[>0;10;1c")
  # DA3 (CSI = c): DECRPTUI unit id, a DCS string (! | DDDDDDDD ST).
  def device_attr_tertiary  = @wr.write("\x1bP!|00000000\x1b\\")

  def report_size(w, h) = (@master.winsize = [h, w])
  def report_position(x, y) = @wr.write("\e[#{y + 1};#{x + 1}R")

  # These are semantically different, though practically similar
  # *currently*. These are separate so they can be treated differently
  # (bracketed etc.) in the future
  def paste(data)    = @wr.write(data)
  def keypress(data) = @wr.write(data)

  def mouse_report(mode, event, x, y, release)
    case mode
    when :digits then mouse_digits(event, x, y, release)
    else # Currently only x10
      mouse_x10(event, x, y)
    end
  end

  def mouse_digits(event, x, y, release)
    @wr.write("\e[<#{event};#{x + 1};#{y + 1}#{release ? "m" : "M"}")
  end

  def mouse_x10(event, x, y)
    raise "FIXME; untested and likely broken; Test w/htop"
    @wr.write("\e[M#{event.to_i.chr}#{x.chr}#{y.chr}")
  end
end
