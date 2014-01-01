require "log_box/version"
require "fluent-logger"
require "pp"

module LogBox
  DEFAULT_TAG = :thread

  def self.log(obj, options = {})
    o = { tag: DEFAULT_TAG, time: Time.now, log: obj }.merge(options)
    tag = o.delete :tag
    init_log_box_tag_if_not tag
    log_box_location[tag] << o
  end

  def self.flush(options = {})
    o = { tag: DEFAULT_TAG }.merge(options)
    tag = o.delete :tag
    o[:logs] = log_box_location[tag]
    flush_to_fluentd o
    delete_log_box_tag tag
  end

  def self.display
    pp log_box_location
  end

  private

  def self.log_box_location
    Thread.current[:_log_box]
  end

  def self.init_log_box_location
    Thread.current[:_log_box] = {}  # key: tag, value: Array of Hash
  end

  def self.init_log_box_if_not
    init_log_box_location if log_box_location.nil?
  end

  def self.init_log_box_tag_if_not(tag = :thread)
    init_log_box_if_not
    log_box_location[tag] ||= []
  end

  def self.delete_log_box_tag(tag = :thread)
    log_box_location.delete tag
  end

  def self.init_log_box_tag(tag = :thread)
    log_box_location[tag] = []
  end

  Logger = Fluent::Logger::FluentLogger.new(nil)

  def self.flush_to_fluentd(result)
    Logger.post 'log_box', result
  end
end
