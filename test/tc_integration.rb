$:.unshift "../lib"
$:.unshift "../ext/sqlite3_api"

require 'test/unit'
require 'benchmark'
require 'sqlite3/database'

class String
  def to_utf16
    result = ""
    self.each_byte { |b| result << b.chr << "\0" }
    result
  end

  def from_utf16
    result = ""
    length.times do |i|
      result << self[i,1] if i % 2 == 0 && self[i] != 0
    end
    result
  end
end

module Integration

  drivers_to_test = ( ENV["SQLITE3_DRIVERS"] || "Native" ).split(',')
  drivers_to_test.each do |driver|

    # == TC_OpenClose =========================================================

    test_case = Class.new( Test::Unit::TestCase ) do 
      define_method( "test_create_close" ) do 
        begin
          db = SQLite3::Database.new( "test-create.db",
            :driver => driver )
          assert File.exist?( "test-create.db" )
          assert_nothing_raised { db.close }
        ensure
          File.delete( "test-create.db" ) rescue nil
        end
      end

      define_method( "test_open_close" ) do 
        begin
          File.open( "test-open.db", "w" ) { |f| }
          assert File.exist?( "test-open.db" )
          db = SQLite3::Database.new( "test-open.db",
            :driver => driver )
          assert_nothing_raised { db.close }
        ensure
          File.delete( "test-open.db" ) rescue nil
        end
      end

      define_method( "test_bad_open" ) do 
        assert_raise( SQLite3::CantOpenException ) do
          SQLite3::Database.new( ".", :driver => driver )
        end
      end
    end
    const_set( "TC_OpenClose_#{driver}", test_case )

    # == TC_Database ==========================================================

    test_case = Class.new( Test::Unit::TestCase ) do 
      define_method( "setup" ) do
        @db = SQLite3::Database.new( "test.db", :driver=>driver )
        @db.transaction do
          @db.execute "create table foo ( a integer primary key, b text )"
          @db.execute "insert into foo ( b ) values ( 'foo' )"
          @db.execute "insert into foo ( b ) values ( 'bar' )"
          @db.execute "insert into foo ( b ) values ( 'baz' )"
        end
      end

      define_method( "teardown" ) do
        @db.close
        File.delete( "test.db" )
      end

      define_method( "test_complete_fail" ) do
        assert !@db.complete?( "select * from foo" )
      end
      define_method( "test_complete_success" ) do
        assert @db.complete?( "select * from foo;" )
      end

      define_method( "test_complete_fail_utf16" ) do
        assert !@db.complete?( "select * from foo".to_utf16+"\0\0", true )
      end
      define_method( "test_complete_success_utf16" ) do
        assert @db.complete?( "select * from foo;".to_utf16+"\0\0", true )
      end

      define_method( "test_errmsg" ) do
        assert_equal "not an error", @db.errmsg
      end

      define_method( "test_errmsg_utf16" ) do
        assert_equal "not an error".to_utf16, @db.errmsg(true)
      end

      define_method( "test_errcode" ) do
        assert_equal 0, @db.errcode
      end

      define_method( "test_trace" ) do
        result = nil
        @db.trace( "data" ) { |data,sql| result = [ data, sql ]; 0 }
        @db.execute "select * from foo"
        assert_equal ["data","select * from foo"], result
      end

      define_method( "test_authorizer_okay" ) do
        @db.authorizer( "data" ) { |data,type,a,b,c,d| 0 }
        rows = @db.execute "select * from foo"
        assert_equal 3, rows.length
      end

      define_method( "test_authorizer_error" ) do
        @db.authorizer( "data" ) { |data,type,a,b,c,d| 1 }
        assert_raise( SQLite3::AuthorizationException ) do
          @db.execute "select * from foo"
        end
      end

      define_method( "test_authorizer_silent" ) do
        @db.authorizer( "data" ) { |data,type,a,b,c,d| 2 }
        rows = @db.execute "select * from foo"
        assert rows.empty?
      end

      define_method( "test_prepare_invalid_syntax" ) do
        assert_raise( SQLite3::SQLException ) do
          @db.prepare "select from foo"
        end
      end

      define_method( "test_prepare_invalid_column" ) do
        assert_raise( SQLite3::SQLException ) do
          @db.prepare "select k from foo"
        end
      end

      define_method( "test_prepare_invalid_table" ) do
        assert_raise( SQLite3::SQLException ) do
          @db.prepare "select * from barf"
        end
      end

      define_method( "test_prepare_no_block" ) do
        stmt = @db.prepare "select * from foo"
        assert stmt.respond_to?(:execute)
        stmt.close
      end

      define_method( "test_prepare_with_block" ) do
        called = false
        @db.prepare "select * from foo" do |stmt|
          called = true
          assert stmt.respond_to?(:execute)
        end
        assert called
      end

      define_method( "test_execute_no_block_no_bind_no_match" ) do
        rows = @db.execute( "select * from foo where a > 100" )
        assert rows.empty?
      end

      define_method( "test_execute_with_block_no_bind_no_match" ) do
        called = false
        @db.execute( "select * from foo where a > 100" ) do |row|
          called = true
        end
        assert !called
      end

      define_method( "test_execute_no_block_with_bind_no_match" ) do
        rows = @db.execute( "select * from foo where a > ?", 100 )
        assert rows.empty?
      end

      define_method( "test_execute_with_block_with_bind_no_match" ) do
        called = false
        @db.execute( "select * from foo where a > ?", 100 ) do |row|
          called = true
        end
        assert !called
      end

      define_method( "test_execute_no_block_no_bind_with_match" ) do
        rows = @db.execute( "select * from foo where a = 1" )
        assert_equal 1, rows.length
      end

      define_method( "test_execute_with_block_no_bind_with_match" ) do
        called = 0
        @db.execute( "select * from foo where a = 1" ) do |row|
          called += 1
        end
        assert_equal 1, called
      end

      define_method( "test_execute_no_block_with_bind_with_match" ) do
        rows = @db.execute( "select * from foo where a = ?", 1 )
        assert_equal 1, rows.length
      end

      define_method( "test_execute_with_block_with_bind_with_match" ) do
        called = 0
        @db.execute( "select * from foo where a = ?", 1 ) do |row|
          called += 1
        end
        assert_equal 1, called
      end

      define_method( "test_execute2_no_block_no_bind_no_match" ) do
        columns, *rows = @db.execute2( "select * from foo where a > 100" )
        assert rows.empty?
        assert [ "a", "b" ], columns
      end

      define_method( "test_execute2_with_block_no_bind_no_match" ) do
        called = 0
        @db.execute2( "select * from foo where a > 100" ) do |row|
          assert [ "a", "b" ], row unless called == 0
          called += 1
        end
        assert_equal 1, called 
      end

      define_method( "test_execute2_no_block_with_bind_no_match" ) do
        columns, *rows = @db.execute2( "select * from foo where a > ?", 100 )
        assert rows.empty?
        assert [ "a", "b" ], columns
      end

      define_method( "test_execute2_with_block_with_bind_no_match" ) do
        called = 0
        @db.execute2( "select * from foo where a > ?", 100 ) do |row|
          assert [ "a", "b" ], row unless called == 0
          called += 1
        end
        assert_equal 1, called
      end

      define_method( "test_execute2_no_block_no_bind_with_match" ) do
        columns, *rows = @db.execute2( "select * from foo where a = 1" )
        assert_equal 1, rows.length
        assert [ "a", "b" ], columns
      end

      define_method( "test_execute2_with_block_no_bind_with_match" ) do
        called = 0
        @db.execute2( "select * from foo where a = 1" ) do |row|
          assert [ "a", "b" ], row unless called == 0
          called += 1
        end
        assert_equal 2, called
      end

      define_method( "test_execute2_no_block_with_bind_with_match" ) do
        columns, *rows = @db.execute2( "select * from foo where a = ?", 1 )
        assert_equal 1, rows.length
        assert [ "a", "b" ], columns
      end

      define_method( "test_execute2_with_block_with_bind_with_match" ) do
        called = 0
        @db.execute2( "select * from foo where a = ?", 1 ) do |row|
          called += 1
        end
        assert_equal 2, called
      end

      define_method( "test_execute_batch_empty" ) do
        assert_nothing_raised { @db.execute_batch "" }
      end

      define_method( "test_execute_batch_no_bind" ) do
        @db.transaction do
          @db.execute_batch <<-SQL
            create table bar ( a, b, c );
            insert into bar values ( 'one', 2, 'three' );
            insert into bar values ( 'four', 5, 'six' );
            insert into bar values ( 'seven', 8, 'nine' );
          SQL
        end
        rows = @db.execute( "select * from bar" )
        assert_equal 3, rows.length
      end

      define_method( "test_execute_batch_with_bind" ) do
        @db.execute_batch( <<-SQL, 1 )
          create table bar ( a, b, c );
          insert into bar values ( 'one', 2, ? );
          insert into bar values ( 'four', 5, ? );
          insert into bar values ( 'seven', 8, ? );
        SQL
        rows = @db.execute( "select * from bar" ).map { |a,b,c| c }
        assert_equal %w{1 1 1}, rows
      end

      define_method( "test_get_first_row_no_bind_no_match" ) do
        result = @db.get_first_row( "select * from foo where a=100" )
        assert_nil result
      end

      define_method( "test_get_first_row_no_bind_with_match" ) do
        result = @db.get_first_row( "select * from foo where a=1" )
        assert_equal [ "1", "foo" ], result
      end

      define_method( "test_get_first_row_with_bind_no_match" ) do
        result = @db.get_first_row( "select * from foo where a=?", 100 )
        assert_nil result
      end

      define_method( "test_get_first_row_with_bind_with_match" ) do
        result = @db.get_first_row( "select * from foo where a=?", 1 )
        assert_equal [ "1", "foo" ], result
      end

      define_method( "test_get_first_value_no_bind_no_match" ) do
        result = @db.get_first_value( "select b, a from foo where a=100" )
        assert_nil result
      end

      define_method( "test_get_first_value_no_bind_with_match" ) do
        result = @db.get_first_value( "select b, a from foo where a=1" )
        assert_equal "foo", result
      end

      define_method( "test_get_first_value_with_bind_no_match" ) do
        result = @db.get_first_value( "select b, a from foo where a=?", 100 )
        assert_nil result
      end

      define_method( "test_get_first_value_with_bind_with_match" ) do
        result = @db.get_first_value( "select b, a from foo where a=?", 1 )
        assert_equal "foo", result
      end

      define_method( "test_last_insert_row_id" ) do
        @db.execute "insert into foo ( b ) values ( 'test' )"
        assert_equal 4, @db.last_insert_row_id
        @db.execute "insert into foo ( b ) values ( 'again' )"
        assert_equal 5, @db.last_insert_row_id
      end

      define_method( "test_changes" ) do
        @db.execute "insert into foo ( b ) values ( 'test' )"
        assert_equal 1, @db.changes
        @db.execute "delete from foo where 1=1"
        assert_equal 4, @db.changes
      end

      define_method( "test_total_changes" ) do
        assert_equal 3, @db.total_changes
        @db.execute "insert into foo ( b ) values ( 'test' )"
        @db.execute "delete from foo where 1=1"
        assert_equal 8, @db.total_changes
      end

      define_method( "test_transaction_nest" ) do
        assert_raise( SQLite3::SQLException ) do
          @db.transaction do
            @db.transaction do
            end
          end
        end
      end

      define_method( "test_transaction_rollback" ) do
        @db.transaction
        @db.execute_batch <<-SQL
          insert into foo (b) values ( 'test1' );
          insert into foo (b) values ( 'test2' );
          insert into foo (b) values ( 'test3' );
          insert into foo (b) values ( 'test4' );
        SQL
        assert_equal 7, @db.get_first_value("select count(*) from foo").to_i
        @db.rollback
        assert_equal 3, @db.get_first_value("select count(*) from foo").to_i
      end

      define_method( "test_transaction_commit" ) do
        @db.transaction
        @db.execute_batch <<-SQL
          insert into foo (b) values ( 'test1' );
          insert into foo (b) values ( 'test2' );
          insert into foo (b) values ( 'test3' );
          insert into foo (b) values ( 'test4' );
        SQL
        assert_equal 7, @db.get_first_value("select count(*) from foo").to_i
        @db.commit
        assert_equal 7, @db.get_first_value("select count(*) from foo").to_i
      end

      define_method( "test_transaction_rollback_in_block" ) do
        assert_raise( SQLite3::SQLException ) do
          @db.transaction do
            @db.rollback
          end
        end
      end

      define_method( "test_transaction_commit_in_block" ) do
        assert_raise( SQLite3::SQLException ) do
          @db.transaction do
            @db.commit
          end
        end
      end

      define_method( "test_transaction_active" ) do
        assert !@db.transaction_active?
        @db.transaction
        assert @db.transaction_active?
        @db.commit
        assert !@db.transaction_active?
      end

      define_method( "no_tests_at" ) do |file,line,method|
        warn "[(#{self.class}):#{file}:#{line}] no tests for #{method}"
      end

      define_method( "test_interrupt" ) do
        @db.create_function( "abort", 1 ) do |func,x|
          @db.interrupt
          func.result = x
        end

        assert_raise( SQLite3::SQLException ) do
          @db.execute "select abort(a) from foo"
        end
      end

      define_method( "test_busy_handler_outwait" ) do
        begin
          db2 = SQLite3::Database.open( "test.db", :driver=>driver )
          handler_call_count = 0
          db2.busy_handler do |data,count|
            handler_call_count += 1
            sleep 0.1
            1
          end

          t = Thread.new do
            @db.transaction( :exclusive ) do
              sleep 0.1
            end
          end

          assert_nothing_raised do
            db2.execute "insert into foo (b) values ( 'from 2' )"
          end

          assert_equal 1, handler_call_count

          t.join
        ensure
          db2.close if db2
        end
      end

      define_method( "test_busy_handler_impatient" ) do
        begin
          db2 = SQLite3::Database.open( "test.db", :driver=>driver )
          handler_call_count = 0
          db2.busy_handler do |data,count|
            handler_call_count += 1
            sleep 0.1
            0
          end

          t = Thread.new do
            @db.transaction( :exclusive ) do
              sleep 0.2
            end
          end

          assert_raise( SQLite3::BusyException ) do
            db2.execute "insert into foo (b) values ( 'from 2' )"
          end

          assert_equal 1, handler_call_count

          t.join
        ensure
          db2.close if db2
        end
      end

      define_method( "test_busy_timeout" ) do
        begin
          db2 = SQLite3::Database.open( "test.db", :driver=>driver )
          db2.busy_timeout 300

          t = Thread.new do
            @db.transaction( :exclusive ) do
              sleep 0.1
            end
          end

          time = Benchmark.measure do
            assert_raise( SQLite3::BusyException ) do
              db2.execute "insert into foo (b) values ( 'from 2' )"
            end
          end
          assert time.real*1000 >= 300

          t.join
        ensure
          db2.close if db2
        end
      end

      define_method( "test_create_function" ) do
        @db.create_function( "munge", 1 ) do |func,x|
          func.result = ">>>#{x}<<<"
        end

        value = @db.get_first_value( "select munge(b) from foo where a=1" )
        assert_match( />>>.*<<</, value )
      end

      define_method( "test_create_aggregate_without_block" ) do
        step = proc do |ctx,a|
          ctx[:sum] ||= 0
          ctx[:sum] += a.to_i
        end

        final = proc { |ctx| ctx.result = ctx[:sum] }

        @db.create_aggregate( "accumulate", 1, step, final )

        value = @db.get_first_value( "select accumulate(a) from foo" )
        assert_equal "6", value
      end

      define_method( "test_create_aggregate_with_block" ) do
        @db.create_aggregate( "accumulate", 1 ) do
          step do |ctx,a|
            ctx[:sum] ||= 0
            ctx[:sum] += a.to_i
          end

          finalize { |ctx| ctx.result = ctx[:sum] }
        end

        value = @db.get_first_value( "select accumulate(a) from foo" )
        assert_equal "6", value
      end

      define_method( "test_create_aggregate_with_no_data" ) do
        @db.create_aggregate( "accumulate", 1 ) do
          step do |ctx,a|
            ctx[:sum] ||= 0
            ctx[:sum] += a.to_i
          end

          finalize { |ctx| ctx.result = ctx[:sum] || 0 }
        end

        value = @db.get_first_value(
          "select accumulate(a) from foo where a = 100" )
        assert_equal "0", value
      end

      define_method( "test_create_aggregate_handler" ) do
        handler = Class.new do
          class << self
            define_method( "arity" ) { 1 }
            define_method( "text_rep" ) { SQLite3::Constants::TextRep::ANY }
            define_method( "name" ) { "multiply" }
          end
          define_method( "step" ) do |ctx,a|
            ctx[:buffer] ||= 1
            ctx[:buffer] *= a.to_i
          end
          define_method( "finalize" ) { |ctx| ctx.result = ctx[:buffer] }
        end

        @db.create_aggregate_handler( handler )
        value = @db.get_first_value( "select multiply(a) from foo" )
        assert_equal "6", value
      end

      define_method( "test_bind_array_parameter" ) do
        result = @db.get_first_value( "select b from foo where a=? and b=?",
          [ 1, "foo" ] )
        assert_equal "foo", result
      end
    end
    const_set( "TC_Database_#{driver}", test_case )

    # == TC_Statement =========================================================

    test_case = Class.new( Test::Unit::TestCase ) do 
      define_method( "setup" ) do
        @db = SQLite3::Database.new( "test.db", :driver=>driver )
        @db.transaction do
          @db.execute "create table foo ( a integer primary key, b text )"
          @db.execute "insert into foo ( b ) values ( 'foo' )"
          @db.execute "insert into foo ( b ) values ( 'bar' )"
          @db.execute "insert into foo ( b ) values ( 'baz' )"
        end
        @stmt = @db.prepare( "select * from foo where a in ( ?, :named )" )
      end

      define_method( "teardown" ) do
        @stmt.close
        @db.close
        File.delete( "test.db" )
      end

      define_method( "test_remainder_empty" ) do
        assert_equal "", @stmt.remainder
      end

      define_method( "test_remainder_nonempty" ) do
        called = false
        @db.prepare( "select * from foo;\n blah" ) do |stmt|
          called = true
          assert_equal "\n blah", stmt.remainder
        end
        assert called
      end

      define_method( "test_bind_params_empty" ) do
        assert_nothing_raised { @stmt.bind_params }
        assert @stmt.execute!.empty?
      end

      define_method( "test_bind_params_array" ) do
        @stmt.bind_params 1, 2
        assert_equal 2, @stmt.execute!.length
      end

      define_method( "test_bind_params_hash" ) do
        @stmt.bind_params ":named" => 2
        assert_equal 1, @stmt.execute!.length
      end

      define_method( "test_bind_params_mixed" ) do
        @stmt.bind_params( 1, ":named" => 2 )
        assert_equal 2, @stmt.execute!.length
      end

      define_method( "test_bind_param_by_index" ) do
        @stmt.bind_params( 1, 2 )
        assert_equal 2, @stmt.execute!.length
      end

      define_method( "test_bind_param_by_name_bad" ) do
        assert_raise( SQLite3::Exception ) { @stmt.bind_param( "named", 2 ) }
      end

      define_method( "test_bind_param_by_name_good" ) do
        @stmt.bind_param( ":named", 2 )
        assert_equal 1, @stmt.execute!.length
      end

      define_method( "test_execute_no_bind_no_block" ) do
        assert_instance_of SQLite3::ResultSet, @stmt.execute
      end

      define_method( "test_execute_with_bind_no_block" ) do
        assert_instance_of SQLite3::ResultSet, @stmt.execute( 1, 2 )
      end

      define_method( "test_execute_no_bind_with_block" ) do
        called = false
        @stmt.execute { |row| called = true }
        assert called
      end

      define_method( "test_execute_with_bind_with_block" ) do
        called = 0
        @stmt.execute( 1, 2 ) { |row| called += 1 }
        assert_equal 1, called
      end

      define_method( "test_reexecute" ) do
        r = @stmt.execute( 1, 2 )
        assert_equal 2, r.to_a.length
        assert_nothing_raised { r = @stmt.execute( 1, 2 ) }
        assert_equal 2, r.to_a.length
      end

      define_method( "test_execute_bang_no_bind_no_block" ) do
        assert @stmt.execute!.empty?
      end

      define_method( "test_execute_bang_with_bind_no_block" ) do
        assert_equal 2, @stmt.execute!( 1, 2 ).length
      end

      define_method( "test_execute_bang_no_bind_with_block" ) do
        called = 0
        @stmt.execute! { |row| called += 1 }
        assert_equal 0, called
      end

      define_method( "test_execute_bang_with_bind_with_block" ) do
        called = 0
        @stmt.execute!( 1, 2 ) { |row| called += 1 }
        assert_equal 2, called
      end

      define_method( "test_columns" ) do
        c1 = @stmt.columns
        c2 = @stmt.columns
        assert_same c1, c2
        assert_equal 2, c1.length
      end

      define_method( "test_columns_computed" ) do
        called = false
        @db.prepare( "select count(*) from foo" ) do |stmt|
          called = true
          assert_equal [ "count(*)" ], stmt.columns
        end
        assert called
      end

      define_method( "test_types" ) do
        t1 = @stmt.types
        t2 = @stmt.types
        assert_same t1, t2
        assert_equal 2, t1.length
      end

      define_method( "test_types_computed" ) do
        called = false
        @db.prepare( "select count(*) from foo" ) do |stmt|
          called = true
          assert_equal [ nil ], stmt.types
        end
        assert called
      end
    end
    const_set( "TC_Statement_#{driver}", test_case )

    # == TC_ResultSet =========================================================

    test_case = Class.new( Test::Unit::TestCase ) do 
      define_method( "setup" ) do
        @db = SQLite3::Database.new( "test.db", :driver=>driver )
        @db.transaction do
          @db.execute "create table foo ( a integer primary key, b text )"
          @db.execute "insert into foo ( b ) values ( 'foo' )"
          @db.execute "insert into foo ( b ) values ( 'bar' )"
          @db.execute "insert into foo ( b ) values ( 'baz' )"
        end
        @stmt = @db.prepare( "select * from foo where a in ( ?, ? )" )
        @result = @stmt.execute
      end

      define_method( "teardown" ) do
        @stmt.close
        @db.close
        File.delete( "test.db" )
      end

      define_method( "test_reset_unused" ) do
        assert_nothing_raised { @result.reset }
        assert @result.to_a.empty?
      end

      define_method( "test_reset_used" ) do
        @result.to_a
        assert_nothing_raised { @result.reset }
        assert @result.to_a.empty?
      end

      define_method( "test_reset_with_bind" ) do
        @result.to_a
        assert_nothing_raised { @result.reset( 1, 2 ) }
        assert_equal 2, @result.to_a.length
      end

      define_method( "test_eof_inner" ) do
        @result.reset( 1 )
        assert !@result.eof?
      end

      define_method( "test_eof_edge" ) do
        @result.reset( 1 )
        @result.next # to first row
        @result.next # to end of result set
        assert @result.eof?
      end

      define_method( "test_next_eof" ) do
        @result.reset( 1 )
        assert_not_nil @result.next
        assert_nil @result.next
      end

      define_method( "test_next_no_type_translation_no_hash" ) do
        @result.reset( 1 )
        assert_equal [ "1", "foo" ], @result.next
      end

      define_method( "test_next_type_translation" ) do
        @db.type_translation = true
        @result.reset( 1 )
        assert_equal [ 1, "foo" ], @result.next
      end

      define_method( "test_next_results_as_hash" ) do
        @db.results_as_hash = true
        @result.reset( 1 )
        assert_equal( { "a" => "1", "b" => "foo", 0 => "1", 1 => "foo" },
          @result.next )
      end

      define_method( "test_each" ) do
        called = 0
        @result.reset( 1, 2 )
        @result.each { |row| called += 1 }
        assert_equal 2, called
      end

      define_method( "test_enumerable" ) do
        @result.reset( 1, 2 )
        assert_equal 2, @result.to_a.length
      end

      define_method( "test_types" ) do
        assert_equal [ "integer", "text" ], @result.types
      end

      define_method( "test_columns" ) do
        assert_equal [ "a", "b" ], @result.columns
      end
    end
    const_set( "TC_ResultSet_#{driver}", test_case )
  end

end