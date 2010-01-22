require 'helper'

module SQLite3
  class TestStatement < Test::Unit::TestCase
    def setup
      @db   = SQLite3::Database.new(':memory:')
      @stmt = SQLite3::Statement.new(@db, "select 'foo'")
    end

    def test_new
      assert @stmt
    end

    def test_new_closed_handle
      @db = SQLite3::Database.new(':memory:')
      @db.close
      assert_raises(ArgumentError) do
        SQLite3::Statement.new(@db, 'select "foo"')
      end
    end

    def test_new_with_remainder
      stmt = SQLite3::Statement.new(@db, "select 'foo';bar")
      assert_equal 'bar', stmt.remainder
    end

    def test_empty_remainder
      assert_equal '', @stmt.remainder
    end

    def test_close
      @stmt.close
      assert @stmt.closed?
    end

    def test_double_close
      @stmt.close
      assert_raises(SQLite3::Exception) do
        @stmt.close
      end
    end

    def test_bind_param_string
      stmt = SQLite3::Statement.new(@db, "select ?")
      stmt.bind_param(1, "hello")
      result = nil
      stmt.each { |x| result = x }
      assert_equal ['hello'], result
    end

    def test_bind_param_int
      stmt = SQLite3::Statement.new(@db, "select ?")
      stmt.bind_param(1, 10)
      result = nil
      stmt.each { |x| result = x }
      assert_equal [10], result
    end

    def test_bind_nil
      stmt = SQLite3::Statement.new(@db, "select ?")
      stmt.bind_param(1, nil)
      result = nil
      stmt.each { |x| result = x }
      assert_equal [nil], result
    end

    def test_bind_64
      stmt = SQLite3::Statement.new(@db, "select ?")
      stmt.bind_param(1, 2 ** 31)
      result = nil
      stmt.each { |x| result = x }
      assert_equal [2 ** 31], result
    end

    def test_bind_double
      stmt = SQLite3::Statement.new(@db, "select ?")
      stmt.bind_param(1, 2.2)
      result = nil
      stmt.each { |x| result = x }
      assert_equal [2.2], result
    end

    def test_named_bind
      stmt = SQLite3::Statement.new(@db, "select :foo")
      stmt.bind_param(':foo', 'hello')
      result = nil
      stmt.each { |x| result = x }
      assert_equal ['hello'], result
    end

    def test_each
      r = nil
      @stmt.each do |row|
        r = row
      end
      assert_equal(['foo'], r)
    end
  end
end