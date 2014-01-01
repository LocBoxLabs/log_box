require "log_box/version"
require "fluent-logger"
require "pp"

module LogBox
  DEFAULT_TAG = :thread

  def self.log(obj, options = {})
    o = { tag: DEFAULT_TAG, time: current_time, log: obj }.merge(options)
    tag = o.delete :tag
    init_log_box_tag_if_not tag
    log_box[tag] << o
  end


  # Following log will be stored into fluentd:
  # {
  #     "_id" : ObjectId("52c4a1f4e1eef37b9900001a"),
  #     "tag" : "delayed_job",
  #     "logs" : [
  #         {
  #             "time" : "2014-01-01 15:16:43 -0800",
  #             "log" : "Ho-ho",
  #             "priority" : 3
  #         }
  #     ],
  #     "time" : ISODate("2014-01-01T23:17:01.000Z")
  # }
  def self.flush(options = {})
    o = { tag: DEFAULT_TAG }.merge(options)
    tag = o[:tag]
    o[:logs] = log_box[tag]
    flush_to_fluentd o
    delete_log_box_tag tag
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

  def self.init_log_box_tag_if_not(tag = :thread)
    init_log_box_if_not
    log_box[tag] ||= []
  end

  def self.delete_log_box_tag(tag = :thread)
    log_box.delete tag
  end

  def self.init_log_box_tag(tag = :thread)
    log_box[tag] = []
  end

  Logger = Fluent::Logger::FluentLogger.new(nil)

  def self.flush_to_fluentd(result)
    Logger.post 'log_box', result
  end
end
