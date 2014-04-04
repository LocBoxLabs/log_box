require "log_box/version"
require "fluent-logger"
require "pp"

class Hash
  def symbolize_keys
    inject({}) do |options, (key, value)|
      value = value.symbolize_keys if defined?(value.symbolize_keys)
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end
end

module LogBox
  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield(configuration)
  end

  DEFAULT_LABEL = :log_box
  DEFAULT_TAG = :thread
  DEFAULT_RECORD_THREAD_ID = true

  class Configuration
    attr_accessor :logger, :default_label, :default_tag, :record_thread_id

    def initialize
      @logger = Fluent::Logger::ConsoleLogger.new(STDOUT)
      @default_label = DEFAULT_LABEL
      @default_tag = DEFAULT_TAG
      @record_thread_id = DEFAULT_RECORD_THREAD_ID
    end
  end

  # Following hash is stored into Thread.current[:_log_box]
  # {
  #  :new_tag =>
  #  [{:time=>2014-01-01 15:38:15 -0800, :log=>"Hi-ho", :priority=>3}],
  #
  #  :thread=>
  #   [{:time=>2014-01-01 15:38:21 -0800, :log=>"Hello"},
  #    {:time=>2014-01-01 15:38:23 -0800, :log=>"Hello2"}]
  # }
  def self.log(obj, options = {})
    return unless logger

=begin
    o = { tag: default_tag,
      time: current_time,
      log: obj.is_a?(String) ? obj : obj.inspect
    }.merge(options).symbolize_keys
=end
    o = { tag: default_tag, time: current_time }.merge(options).symbolize_keys
    if obj.is_a?(String)
      o[:log] = obj
    elsif obj.class < ActiveRecord::Base
      o = o.merge(class: obj.class.to_s).merge(obj.attributes)
    elsif obj.is_a?(Hash)
      o.merge!(obj)
    else
      # o[:log] = obj.inspect
      o[:log] = obj.to_json
    end

    tag = o.delete :tag
    init_log_box_tag_if_not tag
    log_box[tag] << o
    puts "---------- stored in LogBox"
    pp o
  end

  def self.add_attribute(key, value, options = {})
    return unless logger
    o = { tag: default_tag }.merge(options).symbolize_keys
    tag = o[:tag]
    init_log_box_tag_if_not tag
    attributes[tag][key] = value
  end

  # Following log is stored into fluentd:
  # {
  #     "_id" : ObjectId("52c4a1f4e1eef37b9900001a"),
  #     "tag" : "thread",
  #     "logs" : [
  #         {
  #             "time" : "2014-01-01 15:16:43 -0800",
  #             "log" : "Hi-ho",
  #         }
  #     ],
  #     "time" : ISODate("2014-01-01T23:17:01.000Z")
  # }
  def self.flush(options = {})
    return unless logger
    init_log_box_if_not

    o = { tag: default_tag }.merge(options).symbolize_keys
    tag = o[:tag]
    o[:logs] = log_box[tag]
    record_thread_id(o)
    record_runtime(o, tag)
    record_start_at(o, tag)
    record_finish_at(o, tag)
    o.merge!(attributes[tag]) if attributes[tag]
    flush_to_fluentd o
    discard tag
  end

  def self.discard(tag = nil)
    return unless logger

    tag ||= default_tag
    log_box.delete tag
    attributes.delete tag
  end

  def self.display
    pp log_box
    pp attributes
  end

  def self.log_box
    Thread.current[:_log_box]
  end

  def self.attributes
    Thread.current[:_log_box_attributes]
  end

  def self.set_defautl_tag_on_this_thread(tag)
    Thread.current[:_log_box_default_tag] ||= []
    Thread.current[:_log_box_default_tag].push tag
  end

  def self.unset_defautl_tag_on_this_thread
    return unless Thread.current[:_log_box_default_tag]
    Thread.current[:_log_box_default_tag].pop
  end

  private

  def self.default_label
    self.configuration.default_label || DEFAULT_LABEL
  end

  def self.default_tag
    Thread.current[:_log_box_default_tag].try(:[], -1) || self.configuration.default_tag ||
      DEFAULT_TAG
  end

  def self.default_record_thread_id
    self.configuration.record_thread_id || DEFAULT_RECORD_THREAD_ID
  end

  def self.logger
    self.configuration.logger
  end

  def self.current_time
    # unit: milli second
    Time.now.instance_eval { self.to_i * 1000 + (usec/1000) }
  end

  def self.thread_id
    Thread.current.object_id
  end

  def self.process_id
    Process.pid
  end

  def self.record_thread_id(o)
    if self.configuration.record_thread_id
      o[:thread_id] = thread_id
      o[:process_id] = process_id
    end
  end

  def self.start_at(tag)
    return nil unless log_box[tag] && log_box[tag][0]
    log_box[tag][0].try(:[], :time)
  end

  def self.record_start_at(o, tag)
    o[:start_at] = start_at(tag)
  end

  def self.record_finish_at(o, tag)
    o[:finish_at] = current_time
  end

  def self.record_runtime(o, tag)
    o[:runtime] = (current_time - start_at(tag)) / 1000.0 if (start_at(tag) && o[:runtime].nil?)
  end

  def self.init_log_box
    Thread.current[:_log_box] = {}  # key: tag, value: Array of Hash
    Thread.current[:_log_box_attributes] ||= {}
  end

  def self.init_log_box_if_not
    init_log_box if log_box.nil?
  end

  def self.init_log_box_tag_if_not(tag = nil)
    tag ||= default_tag
    init_log_box_if_not
    log_box[tag] ||= []
    attributes[tag] ||= {}
  end

  def self.init_log_box_tag(tag = nil)
    tag ||= default_tag
    log_box[tag] = []
  end

  def self.flush_to_fluentd(result)
    logger.post default_label, result if logger
  end
end
