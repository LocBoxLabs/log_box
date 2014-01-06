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

  class Configuration
    attr_accessor :logger

    def initialize
      @logger = Fluent::Logger::ConsoleLogger.new(STDOUT)
      @default_tag = :thread
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
    o = { tag: self.configuration.default_tag,
      time: current_time,
      log: obj.is_a?(String) ? obj : obj.inspect
    }.merge(options).symbolize_keys

=begin
    o = { tag: self.configuration.default_tag, time: current_time }.merge(options).symbolize_keys
    if obj.is_a?(String)
      o[:log] = obj
    elsif obj.class < ActiveRecord::Base
      o = o.merge(class: obj.class.to_s).merge(obj.attributes)
    elsif obj.is_a?(Hash)
      o.merge!(obj)
    else
      o[:log] = obj.inspect
    end
=end
    tag = o.delete :tag
    init_log_box_tag_if_not tag
    log_box[tag] << o
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
    o = { tag: self.configuration.default_tag }.merge(options).symbolize_keys
    tag = o[:tag]
    o[:logs] = log_box[tag]
    flush_to_fluentd o
    discard tag
  end

  def self.discard(tag = nil)
    tag ||= self.configuration.default_tag
    log_box.delete tag
  end

  def self.display
    pp log_box
  end

  def self.log_box
    Thread.current[:_log_box]
  end


  private

  def self.current_time
    Time.now
  end

  def self.init_log_box
    Thread.current[:_log_box] = {}  # key: tag, value: Array of Hash
  end

  def self.init_log_box_if_not
    init_log_box if log_box.nil?
  end

  def self.init_log_box_tag_if_not(tag = nil)
    tag ||= self.configuration.default_tag
    init_log_box_if_not
    log_box[tag] ||= []
  end

  def self.init_log_box_tag(tag = nil)
    tag ||= self.configuration.default_tag
    log_box[tag] = []
  end

  def self.flush_to_fluentd(result)
    self.configuration.logger.post 'log_box', result
  end
end
