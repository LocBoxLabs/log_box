require 'spec_helper'
require 'log_box'

RSpec::Matchers.define :include_log do |message|
  match do |logs|
    logs ||= []
    logs.include?({time: current_time_, log: message})
  end
end

RSpec::Matchers.define :include_key_value do |key, value|
  match do |logs|
    logs ||= []
    logs.map { |log| log[key] }.include? value
  end
end

describe LogBox do
  let(:current_time_) { '2014-01-23' }
  let(:default_tag_) { LogBox::DEFAULT_TAG }

  let(:new_tag_) { :new_tag }

  let(:message_1_) { 'hello 1' }
  let(:message_2_) { 'hello 2' }

  class DummyLogger
    def initialize(); end
    def post(tag, result); end
  end

  before do
    LogBox.configure do |config| config.logger = DummyLogger.new end
    LogBox.send(:init_log_box)
    LogBox.stub(:current_time).and_return(current_time_)
  end

  def verify(message, tag = default_tag_)
    expect(LogBox.log_box[tag]).to include_log(message)
  end

  def verify_not(message, tag = default_tag_)
    expect(LogBox.log_box[tag]).not_to include_log(message)
  end

  def log(message, options = {})
    LogBox.log message, options
  end

  def try_flush(expected = {})
    tag = expected.delete(:tag) || default_tag_
    LogBox.should_receive(:flush_to_fluentd) do |obj_to_fluentd|
      expect(obj_to_fluentd[:tag]).to eq(tag)
      expect(obj_to_fluentd).to have_key(:logs)
      expected.each_pair do |key, value|
        expect(obj_to_fluentd[:logs]).to include_key_value(key, value)
      end
    end
    LogBox.flush tag: tag
  end

  context 'one box' do
    describe '#log' do
      it 'init_log_box' do
        log message_1_
        LogBox.send(:init_log_box)
        verify_not message_1_
      end

      it 'default tag' do
        log message_1_
        verify message_1_
        verify_not message_2_

        log message_2_
        verify message_1_
        verify message_2_
      end

      it 'new tag' do
        log message_1_, tag: new_tag_
        verify message_1_, new_tag_
        verify_not message_1_
      end

      it 'additional key value' do
        log message_1_, tag: new_tag_, new_key: 'new_value'
        expect(LogBox.log_box[new_tag_]).to include_key_value(:new_key, 'new_value')
      end
    end

    describe '#flush' do
      it 'default tag' do
        log message_1_
        try_flush log: message_1_
      end

      it '2 logs' do
        log message_1_
        log message_2_
        try_flush log: message_1_, log: message_2_
      end
    end
  end

  context 'multiple boxes' do
    describe '#log' do
      it 'default, new_tag' do
        log message_1_
        log message_2_, tag: new_tag_

        verify message_1_
        verify_not message_2_

        verify message_2_, new_tag_
        verify_not message_1_, new_tag_
      end
    end

    describe '#flush' do
      it 'default, new_tag' do
        log message_1_
        log message_2_, tag: new_tag_

        try_flush tag: default_tag_, log: message_1_
        try_flush tag: new_tag_, log: message_2_
      end
    end
  end
end
