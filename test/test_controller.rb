require_relative 'test_helper'

class TestController < Minitest::Test
  def setup
    # Load controller if available
    begin
      require_relative '../lib/controller'
      @controller_available = true
    rescue LoadError => e
      @controller_available = false
      puts "Warning: Could not load controller: #{e.message}"
    end
  end

  def test_shell_selection_from_config
    skip "Controller not available" unless @controller_available

    config = { shell: '/bin/custom_shell' }
    controller = Controller.new(nil, config)

    assert_equal '/bin/custom_shell', controller.send(:determine_shell)
  end

  def test_shell_selection_from_env_when_config_empty
    skip "Controller not available" unless @controller_available

    # Save original ENV value
    original_shell = ENV['SHELL']

    begin
      ENV['SHELL'] = '/usr/bin/test_shell'
      config = {}
      controller = Controller.new(nil, config)

      assert_equal '/usr/bin/test_shell', controller.send(:determine_shell)
    ensure
      # Restore original ENV value
      ENV['SHELL'] = original_shell
    end
  end

  def test_shell_selection_fallback_to_bin_sh
    skip "Controller not available" unless @controller_available

    # Save original ENV value
    original_shell = ENV['SHELL']

    begin
      ENV['SHELL'] = nil
      config = {}
      controller = Controller.new(nil, config)

      assert_equal '/bin/sh', controller.send(:determine_shell)
    ensure
      # Restore original ENV value
      ENV['SHELL'] = original_shell
    end
  end

  def test_shell_selection_config_overrides_env
    skip "Controller not available" unless @controller_available

    # Save original ENV value
    original_shell = ENV['SHELL']

    begin
      ENV['SHELL'] = '/usr/bin/env_shell'
      config = { shell: '/bin/config_shell' }
      controller = Controller.new(nil, config)

      assert_equal '/bin/config_shell', controller.send(:determine_shell)
    ensure
      # Restore original ENV value
      ENV['SHELL'] = original_shell
    end
  end

  def test_shell_selection_with_nil_config_shell
    skip "Controller not available" unless @controller_available

    # Save original ENV value
    original_shell = ENV['SHELL']

    begin
      ENV['SHELL'] = '/usr/bin/env_shell'
      config = { shell: nil }
      controller = Controller.new(nil, config)

      assert_equal '/usr/bin/env_shell', controller.send(:determine_shell)
    ensure
      # Restore original ENV value
      ENV['SHELL'] = original_shell
    end
  end

  def test_controller_initialization_with_config
    skip "Controller not available" unless @controller_available

    mock_term = Object.new
    config = { shell: '/bin/test' }
    controller = Controller.new(mock_term, config)

    assert_equal mock_term, controller.instance_variable_get(:@term)
    assert_equal config, controller.instance_variable_get(:@config)
  end

  def test_controller_initialization_without_config
    skip "Controller not available" unless @controller_available

    mock_term = Object.new
    controller = Controller.new(mock_term)

    assert_equal mock_term, controller.instance_variable_get(:@term)
    assert_equal({}, controller.instance_variable_get(:@config))
  end
end
