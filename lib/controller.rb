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
    @master, @wr, @pid = *PTY.spawn(*cmd)

    p "Controller: #{@master}"
    Thread.new do
      loop do
        begin
          @term.write(self.read)
          Thread.pass
        rescue Errno::EIO => e
          p e
          # FIXME: Not sure if this really belongs *here*?
          exit(Process.wait(@pid))
        end
      end
    end
  end

  def read
    @master.read_nonblock(128)
  rescue IO::EAGAINWaitReadable
    IO.select([@master], [], [], nil)
    retry
  end

  def device_report
    # Minimum needed to prevent apps expecting a response from hanging
    @wr.write("\x1bP!|00000000")
  end

  def report_size(w, h) = (@master.winsize = [h + 1, w])
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
    p "\e[<#{event};#{x + 1};#{y + 1}#{release ? "m" : "M"}"
    @wr.write("\e[<#{event};#{x + 1};#{y + 1}#{release ? "m" : "M"}")
  end

  def mouse_x10(event, x, y)
    raise "FIXME; untested and likely broken; Test w/htop"
    @wr.write("\e[M#{event.to_i.chr}#{x.chr}#{y.chr}")
  end
end
