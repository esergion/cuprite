# frozen_string_literal: true

require "json"
require "socket"
require "forwardable"
require "websocket/driver"

module Capybara::Cuprite
  class Browser
    class WebSocket
      extend Forwardable

      delegate close: :@driver

      attr_reader :url, :events

      def initialize(url, logger)
        @url    = url
        @logger = logger
        uri     = URI.parse(@url)
        @sock   = TCPSocket.new(uri.host, uri.port)
        @driver = ::WebSocket::Driver.client(self)

        @events     = Queue.new
        @dead       = false

        @driver.on(:message, &method(:on_message))
        @driver.on(:error, &method(:on_error))
        @driver.on(:close, &method(:on_close))

        @thread = Thread.new do
          begin
            until @dead
              data = @sock.readpartial(512)
              @driver.parse(data)
            end
          rescue EOFError
          end
        end

        @driver.start
      end

      def send_message(data)
        json = data.to_json
        log "\n\n>>> #{json}"
        @driver.text(json)
      end

      def on_message(event)
        log "    <<< #{event.data}\n"
        data = JSON.parse(event.data)
        @events << data
      end

      # Not sure if CDP uses it at all as all errors go to on_message callback
      # for example: {"error":{"code":-32000,"message":"No node with given id found"},"id":22}
      # FIXME: Raise and close connection and then kill the browser as this
      # would be the error not in the main thread?
      def on_error(event)
        raise event.inspect
      end

      def on_close(event)
        log "<<< #{event.code}, #{event.reason}\n\n"
        @dead = true
        @thread.kill
      end

      def write(data)
        @sock.write(data)
      end

      private

      def log(message)
        @logger.write(message) if @logger
      end
    end
  end
end
