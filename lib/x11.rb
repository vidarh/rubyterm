
class Connection
  attr_reader :display

  def initialize display = ENV["DISPLAY"] || ":0"
    @display = display
  end
end

c = Connection.new
p c.display
