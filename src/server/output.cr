module HTTP
  class Server
    # :nodoc:
    abstract class Output
      include IO::Buffered

      def unbuffered_read(bytes : Bytes)
        raise "can't read from HTTP::Server::Response"
      end

      def unbuffered_rewind
        raise "can't rewind HTTP::Server::Response"
      end

      # abstract def upgrade(protocol : String, &block)
    end

    # :nodoc:
    class LegacyOutput < Output
      def initialize(@connection : HTTP1::Connection, @headers : HTTP::Headers)
        @sent_headers = false
        @chunked = false
      end

      def unbuffered_write(bytes : Bytes)
        unless @sent_headers
          @sent_headers = true
          if @connection.version == "HTTP/1.1" && !@headers.has_key?("content-length")
            @chunked = true
            @headers.add("transfer-encoding", "chunked")
          end
          @connection.send_headers(@headers)
        end
        @connection.send_data(bytes, @chunked)
      end

      def unbuffered_flush
        @connection.flush
      end

      def close
        unless @sent_headers
          @headers["content-length"] = @out_count.to_s
        end
        super
      end

      def unbuffered_close
        @connection.send_data("", @chunked) if @chunked
        @connection.flush
      end

      def upgrade(protocol : String)
        if @sent_headers
          raise ArgumentError.new("Can't upgrade HTTP/1 connection: headers have already been sent")
        end

        @headers[":status"] = "101"
        @headers["connection"] = "Upgrade"
        @headers["upgrade"] = protocol
        @connection.send_headers(@headers)
        @connection.flush

        yield @connection.io
      end
    end

    # :nodoc:
    class StreamOutput < Output
      def initialize(@stream : HTTP2::Stream, @headers : HTTP::Headers)
        @sent_headers = false
      end

      def unbuffered_write(bytes : Bytes)
        unless @sent_headers
          @sent_headers = true
          @stream.send_headers(@headers)
        end
        @stream.send_data(bytes)
        bytes.size
      end

      def close
        unless @sent_headers
          @headers["content-length"] = @out_count.to_s
        end
        super
      end

      def unbuffered_flush
      end

      def unbuffered_close
        @stream.send_data("", flags: HTTP2::Frame::Flags::END_STREAM)
        @stream.send_rst_stream(HTTP2::Error::Code::NO_ERROR)
      end

      def upgrade(protocol : String, &block)
        raise ArgumentError.new("Can't upgrade HTTP/2 connection")
      end
    end
  end
end
