require_relative '../helper'
require 'fluent/plugin/output'
require 'fluent/plugin/buffer'
require 'fluent/msgpack_factory'
require 'fluent/event'

require 'json'
require 'time'
require 'timeout'

require 'flexmock/test_unit'

module FluentPluginStandardBufferedOutputTest
  class DummyBareOutput < Fluent::Plugin::Output
    def register(name, &block)
      instance_variable_set("@#{name}", block)
    end
  end
  class DummyAsyncOutput < DummyBareOutput
    def format(tag, time, record)
      @format ? @format.call(tag, time, record) : [tag, time, record].to_json
    end
    def write(chunk)
      @write ? @write.call(chunk) : nil
    end
  end
  class DummyAsyncStandardOutput < DummyBareOutput
    def write(chunk)
      @write ? @write.call(chunk) : nil
    end
  end
end

class StandardBufferedOutputTest < Test::Unit::TestCase
  def create_output(type=:full)
    case type
    when :bare     then FluentPluginStandardBufferedOutputTest::DummyBareOutput.new
    when :buffered then FluentPluginStandardBufferedOutputTest::DummyAsyncOutput.new
    when :standard then FluentPluginStandardBufferedOutputTest::DummyAsyncStandardOutput.new
    else
      raise ArgumentError, "unknown type: #{type}"
    end
  end
  def create_metadata(timekey: nil, tag: nil, variables: nil)
    Fluent::Plugin::Buffer::Metadata.new(timekey, tag, variables)
  end
  def waiting(seconds)
    begin
      Timeout.timeout(seconds) do
        yield
      end
    rescue Timeout::Error
      STDERR.print *(@i.log.out.logs)
      raise
    end
  end
  def test_event_stream
    es = Fluent::MultiEventStream.new
    es.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
    es.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})
    es.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
    es.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
    es.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
    es.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
    es
  end

  teardown do
    if @i
      @i.stop unless @i.stopped?
      @i.before_shutdown unless @i.before_shutdown?
      @i.shutdown unless @i.shutdown?
      @i.after_shutdown unless @i.after_shutdown?
      @i.close unless @i.closed?
      @i.terminate unless @i.terminated?
    end
  end

  sub_test_case 'standard buffered without any chunk keys' do
    test '#execute_chunking calls @buffer.emit_bulk just once with predefined msgpack format' do
      @i = create_output(:standard)
      @i.configure(config_element())
      @i.start

      m = create_metadata()
      es = test_event_stream

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).once.with(m, es.to_msgpack_stream, es.size)

      @i.execute_chunking("mytag.test", es)
    end

    test '#execute_chunking calls @buffer.emit_bulk just once with predefined msgpack format, but time will be int if time_as_integer specified' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{"time_as_integer"=>"true"}))
      @i.start

      m = create_metadata()
      es = test_event_stream

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).once.with(m, es.to_msgpack_stream(time_int: true), es.size)

      @i.execute_chunking("mytag.test", es)
    end
  end

  sub_test_case 'standard buffered with tag chunk key' do
    test '#execute_chunking calls @buffer.emit_bulk just once with predefined msgpack format' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{},[config_element('buffer','tag')]))
      @i.start

      m = create_metadata(tag: "mytag.test")
      es = test_event_stream

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).once.with(m, es.to_msgpack_stream, es.size)

      @i.execute_chunking("mytag.test", es)
    end

    test '#execute_chunking calls @buffer.emit_bulk just once with predefined msgpack format, but time will be int if time_as_integer specified' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{"time_as_integer"=>"true"},[config_element('buffer','tag')]))
      @i.start

      m = create_metadata(tag: "mytag.test")
      es = test_event_stream

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).once.with(m, es.to_msgpack_stream(time_int: true), es.size)

      @i.execute_chunking("mytag.test", es)
    end
  end

  sub_test_case 'standard buffered with time chunk key' do
    test '#execute_chunking calls @buffer.emit_bulk in times of # of time ranges with predefined msgpack format' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{},[config_element('buffer','time',{"timekey_range" => "60"})]))
      @i.start

      m1 = create_metadata(timekey: Time.parse('2016-04-21 17:19:00 -0700').to_i)
      m2 = create_metadata(timekey: Time.parse('2016-04-21 17:20:00 -0700').to_i)
      m3 = create_metadata(timekey: Time.parse('2016-04-21 17:21:00 -0700').to_i)

      es1 = Fluent::MultiEventStream.new
      es1.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      es2 = Fluent::MultiEventStream.new
      es2.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es2.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      es3 = Fluent::MultiEventStream.new
      es3.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).with(m1, es1.to_msgpack_stream, 3).once
      buffer_mock.should_receive(:emit_bulk).with(m2, es2.to_msgpack_stream, 2).once
      buffer_mock.should_receive(:emit_bulk).with(m3, es3.to_msgpack_stream, 1).once

      es = test_event_stream
      @i.execute_chunking("mytag.test", es)
    end

    test '#execute_chunking calls @buffer.emit_bulk in times of # of time ranges with predefined msgpack format, but time will be int if time_as_integer specified' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{"time_as_integer" => "true"},[config_element('buffer','time',{"timekey_range" => "60"})]))
      @i.start

      m1 = create_metadata(timekey: Time.parse('2016-04-21 17:19:00 -0700').to_i)
      m2 = create_metadata(timekey: Time.parse('2016-04-21 17:20:00 -0700').to_i)
      m3 = create_metadata(timekey: Time.parse('2016-04-21 17:21:00 -0700').to_i)

      es1 = Fluent::MultiEventStream.new
      es1.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      es2 = Fluent::MultiEventStream.new
      es2.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es2.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      es3 = Fluent::MultiEventStream.new
      es3.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).with(m1, es1.to_msgpack_stream(time_int: true), 3).once
      buffer_mock.should_receive(:emit_bulk).with(m2, es2.to_msgpack_stream(time_int: true), 2).once
      buffer_mock.should_receive(:emit_bulk).with(m3, es3.to_msgpack_stream(time_int: true), 1).once

      es = test_event_stream
      @i.execute_chunking("mytag.test", es)
    end
  end

  sub_test_case 'standard buffered with variable chunk keys' do
    test '#execute_chunking calls @buffer.emit_bulk in times of # of variable variations with predefined msgpack format' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{},[config_element('buffer','key,name')]))
      @i.start

      m1 = create_metadata(variables: {key: "my value", name: "moris1"})
      es1 = Fluent::MultiEventStream.new
      es1.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      m2 = create_metadata(variables: {key: "my value", name: "moris2"})
      es2 = Fluent::MultiEventStream.new
      es2.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).with(m1, es1.to_msgpack_stream, 5).once
      buffer_mock.should_receive(:emit_bulk).with(m2, es2.to_msgpack_stream, 1).once

      es = test_event_stream
      @i.execute_chunking("mytag.test", es)
    end

    test '#execute_chunking calls @buffer.emit_bulk in times of # of variable variations with predefined msgpack format, but time will be int if time_as_integer specified' do
      @i = create_output(:standard)
      @i.configure(config_element('ROOT','',{"time_as_integer" => "true"},[config_element('buffer','key,name')]))
      @i.start

      m1 = create_metadata(variables: {key: "my value", name: "moris1"})
      es1 = Fluent::MultiEventStream.new
      es1.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      m2 = create_metadata(variables: {key: "my value", name: "moris2"})
      es2 = Fluent::MultiEventStream.new
      es2.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).with(m1, es1.to_msgpack_stream(time_int: true), 5).once
      buffer_mock.should_receive(:emit_bulk).with(m2, es2.to_msgpack_stream(time_int: true), 1).once

      es = test_event_stream
      @i.execute_chunking("mytag.test", es)
    end
  end

  sub_test_case 'custom format buffered without any chunk keys' do
    test '#execute_chunking calls @buffer.emit_bulk just once with customized format' do
      @i = create_output(:buffered)
      @i.register(:format){|tag, time, record| [time, record].to_json }
      @i.configure(config_element())
      @i.start

      m = create_metadata()
      es = test_event_stream

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).once.with(m, es.map{|t,r| [t,r].to_json }.join, es.size)

      @i.execute_chunking("mytag.test", es)
    end
  end

  sub_test_case 'custom format buffered with tag chunk key' do
    test '#execute_chunking calls @buffer.emit_bulk just once with customized format' do
      @i = create_output(:buffered)
      @i.register(:format){|tag, time, record| [time, record].to_json }
      @i.configure(config_element('ROOT','',{},[config_element('buffer','tag')]))
      @i.start

      m = create_metadata(tag: "mytag.test")
      es = test_event_stream

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit_bulk).once.with(m, es.map{|t,r| [t,r].to_json }.join, es.size)

      @i.execute_chunking("mytag.test", es)
    end
  end
  sub_test_case 'custom format buffered with time chunk key' do
    test '#execute_chunking calls @buffer.emit in times of # of time ranges with customized format' do
      @i = create_output(:buffered)
      @i.register(:format){|tag, time, record| [time, record].to_json }
      @i.configure(config_element('ROOT','',{},[config_element('buffer','time',{"timekey_range" => "60"})]))
      @i.start

      m1 = create_metadata(timekey: Time.parse('2016-04-21 17:19:00 -0700').to_i)
      m2 = create_metadata(timekey: Time.parse('2016-04-21 17:20:00 -0700').to_i)
      m3 = create_metadata(timekey: Time.parse('2016-04-21 17:21:00 -0700').to_i)

      es1 = Fluent::MultiEventStream.new
      es1.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      es2 = Fluent::MultiEventStream.new
      es2.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es2.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      es3 = Fluent::MultiEventStream.new
      es3.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit).with(m1, es1.map{|t,r| [t,r].to_json }).once
      buffer_mock.should_receive(:emit).with(m2, es2.map{|t,r| [t,r].to_json }).once
      buffer_mock.should_receive(:emit).with(m3, es3.map{|t,r| [t,r].to_json }).once

      es = test_event_stream
      @i.execute_chunking("mytag.test", es)
    end
  end

  sub_test_case 'custom format buffered with variable chunk keys' do
    test '#execute_chunking calls @buffer.emit in times of # of variable variations with customized format' do
      @i = create_output(:buffered)
      @i.register(:format){|tag, time, record| [time, record].to_json }
      @i.configure(config_element('ROOT','',{},[config_element('buffer','key,name')]))
      @i.start

      m1 = create_metadata(variables: {key: "my value", name: "moris1"})
      es1 = Fluent::MultiEventStream.new
      es1.add(event_time('2016-04-21 17:19:00 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:19:25 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:20:01 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:20:13 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})
      es1.add(event_time('2016-04-21 17:21:32 -0700'), {"key" => "my value", "name" => "moris1", "message" => "hello!"})

      m2 = create_metadata(variables: {key: "my value", name: "moris2"})
      es2 = Fluent::MultiEventStream.new
      es2.add(event_time('2016-04-21 17:19:13 -0700'), {"key" => "my value", "name" => "moris2", "message" => "hello!"})

      buffer_mock = flexmock(@i.buffer)
      buffer_mock.should_receive(:emit).with(m1, es1.map{|t,r| [t,r].to_json }).once
      buffer_mock.should_receive(:emit).with(m2, es2.map{|t,r| [t,r].to_json }).once

      es = test_event_stream
      @i.execute_chunking("mytag.test", es)
    end
  end
end
