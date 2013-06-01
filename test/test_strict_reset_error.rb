require 'redshift'

include RedShift

require 'minitest/autorun'

# See also test_strict_continuity.rb.

class TestStrictnessError < Minitest::Test

  class T < Component

    strictly_continuous :x

    transition do
      reset :x => 1
    end

  end
  
  # This is the only test that can appear in this file.
  def test_strict_reset_error
    assert_raises(RedShift::StrictnessError) do
      World.new
    end
  end

end
