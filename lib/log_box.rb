require "fluent-logger"
require "log_box/version"

module LogBox
  def self.log(obj, tag = :thread)
    init_log_box_tag_if_not tag
    log_box_location[tag] << { time: Time.now, log: obj }
  end

  def self.flush(tag = :thread)
    result = {}.tap { |hash|
      hash[:tag] = tag
      hash[:logs] = log_box_location[tag]
    }
    flush_to_fluentd result
    init_log_box_tag tag
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

  def self.init_log_box_tag(tag = :thread)
    log_box_location[tag] = []
  end

  Logger = Fluent::Logger::FluentLogger.new(nil)

  def self.flush_to_fluentd(result)
    Logger.post 'log_box', result
  end
end
