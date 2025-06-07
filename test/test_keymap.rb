require_relative 'test_helper'

class TestKeymap < Minitest::Test
  def test_keymap_placeholder
    # Keymap requires X11 dependencies, so we'll skip for now
    skip "Keymap requires X11 dependencies"
  end
end